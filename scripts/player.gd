class_name Player
extends Node3D
## Un joueur : une pastille qui suit un chemin d'ordres avec inertie.
## Le joueur ne se pilote pas directement : on lui donne des points de passage et une allure.

signal orders_changed

enum Allure { MARCHE, TROT, SPRINT }

const ALLURE_SPEED := {
	Allure.MARCHE: 1.8,
	Allure.TROT: 4.5,
	Allure.SPRINT: 8.0,
}
const ACCEL := 5.0  # m/s²
const DECEL := 9.0  # m/s²
const REACH_RADIUS := 0.6  # m
const TURN_RATE_STILL := 7.0  # rad/s à l'arrêt
const TURN_RATE_FAST := 1.4  # rad/s à pleine vitesse
const RADIUS := 0.5
const HEIGHT := 1.8

var team := 0
var is_keeper := false
var stats := {
	"vitesse": 60,
	"endurance": 60,
	"force": 60,
	"agilite": 60,
	"technique": 60,
	"passe": 60,
	"frappe": 60,
	"defense": 60,
	"tete": 60,
	"vision": 60,
	"sang_froid": 60,
}
var speed := 0.0
var heading := Vector3.RIGHT
## Liste de {"pos": Vector3, "allure": int}
var orders: Array = []

var _ring: MeshInstance3D


func setup(p_team: int, p_keeper: bool, color: Color) -> void:
	team = p_team
	is_keeper = p_keeper
	heading = Vector3.RIGHT if team == 0 else Vector3.LEFT
	rotation.y = atan2(heading.x, heading.z)

	var body := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS
	cylinder.bottom_radius = RADIUS
	cylinder.height = HEIGHT
	body.mesh = cylinder
	body.position.y = HEIGHT / 2.0
	body.material_override = _material(color.lightened(0.35) if p_keeper else color)
	add_child(body)

	# Petit repère qui montre la direction du regard.
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.4)
	nose.mesh = box
	nose.position = Vector3(0.0, HEIGHT * 0.7, RADIUS)
	nose.material_override = _material(Color.WHITE)
	add_child(nose)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.9
	_ring.mesh = torus
	_ring.position.y = 0.03
	_ring.material_override = _material(Color(1.0, 0.9, 0.2))
	_ring.visible = false
	add_child(_ring)


func set_selected(value: bool) -> void:
	_ring.visible = value


func top_speed() -> float:
	return ALLURE_SPEED[Allure.SPRINT] * speed_factor()


func speed_factor() -> float:
	# La stat de vitesse (0-100) module la vitesse de pointe entre 80 % et 120 %.
	return 0.8 + 0.4 * float(stats["vitesse"]) / 100.0


func add_order(pos: Vector3, allure: int) -> void:
	orders.append({"pos": Vector3(pos.x, 0.0, pos.z), "allure": allure})
	orders_changed.emit()


func clear_orders() -> void:
	orders.clear()
	orders_changed.emit()


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	var changed := false
	while not orders.is_empty() and _flat_distance_to(orders[0]["pos"]) < REACH_RADIUS:
		orders.pop_front()
		changed = true
	if changed:
		orders_changed.emit()

	var desired_speed := 0.0
	if not orders.is_empty():
		var to_target: Vector3 = orders[0]["pos"] - position
		to_target.y = 0.0
		var distance := to_target.length()
		var direction := to_target / distance

		# L'inertie limite la vitesse de rotation : plus on va vite, moins on tourne.
		var turn_rate := lerpf(TURN_RATE_STILL, TURN_RATE_FAST, clampf(speed / top_speed(), 0.0, 1.0))
		var angle := heading.signed_angle_to(direction, Vector3.UP)
		var turn := clampf(angle, -turn_rate * delta, turn_rate * delta)
		heading = heading.rotated(Vector3.UP, turn).normalized()

		desired_speed = ALLURE_SPEED[orders[0]["allure"]] * speed_factor()
		# Virage serré : on ralentit tant que le joueur n'est pas aligné.
		var misalignment := absf(angle)
		if misalignment > 0.5:
			var cap := lerpf(4.5, 1.0, clampf((misalignment - 0.5) / 1.5, 0.0, 1.0))
			desired_speed = minf(desired_speed, cap)
		# Dernier point : on freine pour s'arrêter dessus.
		if orders.size() == 1:
			desired_speed = minf(desired_speed, sqrt(2.0 * DECEL * 0.8 * distance))

	if speed < desired_speed:
		speed = minf(desired_speed, speed + ACCEL * delta)
	else:
		speed = maxf(desired_speed, speed - DECEL * delta)

	position += heading * speed * delta
	position.y = 0.0
	rotation.y = atan2(heading.x, heading.z)


func _flat_distance_to(point: Vector3) -> float:
	return Vector2(point.x - position.x, point.z - position.z).length()


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
