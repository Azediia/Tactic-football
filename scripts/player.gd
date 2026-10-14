class_name Player
extends Node3D
## Un joueur : une pastille qui exécute une file d'ordres (courir, passer, tirer, tacler)
## avec inertie. Quand il n'a pas d'ordre, l'IA de l'arbitre de jeu lui donne un objectif.

signal orders_changed

enum Allure { MARCHE, TROT, SPRINT }

const ALLURE_SPEED := {
	Allure.MARCHE: 1.8,
	Allure.TROT: 4.5,
	Allure.SPRINT: 8.0,
}
const ALLURE_NAMES := ["Marche", "Trot", "Sprint"]
const ACCEL := 5.0  # m/s²
const DECEL := 9.0  # m/s²
const REACH_RADIUS := 0.6  # m
const TURN_RATE_STILL := 7.0  # rad/s à l'arrêt
const TURN_RATE_FAST := 1.4  # rad/s à pleine vitesse
const RADIUS := 0.65
const HEIGHT := 1.8
const TOUCH_INTERVAL := 0.33  # s entre deux touches de balle en conduite
const TACKLE_RANGE := 1.5  # m
const ORDER_TIMEOUT := 10.0  # s d'attente maximale d'un ordre qui exige le ballon

var team := 0
var role := "ATT"
var is_keeper := false
var display_name := ""
var number := 0
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
	"reflexes": 50,
	"placement": 50,
	"prise": 50,
}
var stamina := 100.0  # 0-100, une seule barre sur la durée du match
var speed := 0.0
var heading := Vector3.RIGHT
## File d'ordres : {"type": "move"|"pass"|"shoot"|"tackle", ...}
var orders: Array = []
## Objectif donné par l'IA quand il n'y a pas d'ordre : {"pos", "allure", "final"} ou null.
var ai_goal = null
var director  # MatchDirector, non typé pour éviter une dépendance circulaire
var stun_time := 0.0
var tackle_cooldown := 0.0
var contact_lock := 0.0
var touch_timer := 0.0
var wait_time := 0.0
var decision_timer := 0.0
## Temps passé au pied du ballon sans ordre (l'équipe pilotée attend ses ordres avant de jouer seule).
var hold_idle := 0.0
var last_eval_shot := -1
var pending_save: Dictionary = {}
var dive: Dictionary = {}

var _body: MeshInstance3D
var _ring: MeshInstance3D


func setup(p_team: int, p_role: String, color: Color, p_name: String, p_number: int) -> void:
	team = p_team
	role = p_role
	is_keeper = p_role == "GK"
	display_name = p_name
	number = p_number
	heading = Vector3.RIGHT if team == 0 else Vector3.LEFT
	rotation.y = atan2(heading.x, heading.z)

	_body = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS
	cylinder.bottom_radius = RADIUS
	cylinder.height = HEIGHT
	_body.mesh = cylinder
	_body.position.y = HEIGHT / 2.0
	_body.material_override = _material(color.lightened(0.4) if is_keeper else color)
	add_child(_body)

	# Repère de direction du regard.
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.4)
	nose.mesh = box
	nose.material_override = _material(Color.WHITE)
	_body.add_child(nose)
	nose.position = Vector3(0.0, 0.5, RADIUS)

	var label := Label3D.new()
	label.text = str(number)
	label.font_size = 64
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 14
	label.position = Vector3(0.0, HEIGHT + 0.9, 0.0)
	add_child(label)

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


## Statistique effective : la fatigue retire jusqu'à 25 points.
func effective_stat(key: String) -> float:
	return maxf(1.0, float(stats[key]) - (100.0 - stamina) * 0.25)


func speed_factor() -> float:
	return (0.8 + 0.4 * float(stats["vitesse"]) / 100.0) * (0.85 + 0.15 * stamina / 100.0)


func top_speed() -> float:
	return ALLURE_SPEED[Allure.SPRINT] * speed_factor()


func control_radius() -> float:
	var skill := float(stats["prise"]) if is_keeper else float(stats["technique"])
	var base := 0.75 + 0.004 * skill
	base *= 0.9 + 0.1 * stamina / 100.0
	return base + (0.3 if is_keeper else 0.0)


# --- Ordres --------------------------------------------------------------------------------

func add_order(pos: Vector3, allure: int) -> void:
	orders.append({"type": "move", "pos": Vector3(pos.x, 0.0, pos.z), "allure": allure})
	orders_changed.emit()


func add_action_order(order: Dictionary) -> void:
	orders.append(order)
	orders_changed.emit()


func clear_orders() -> void:
	orders.clear()
	wait_time = 0.0
	orders_changed.emit()


func has_orders() -> bool:
	return not orders.is_empty()


## Position prévue en fin de file d'ordres (origine d'un nouvel ordre).
func planned_position() -> Vector3:
	for i in range(orders.size() - 1, -1, -1):
		if orders[i]["type"] == "move":
			return orders[i]["pos"]
	return position


# --- Simulation ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	stun_time = maxf(0.0, stun_time - delta)
	tackle_cooldown = maxf(0.0, tackle_cooldown - delta)
	contact_lock = maxf(0.0, contact_lock - delta)
	decision_timer = maxf(0.0, decision_timer - delta)

	if not dive.is_empty():
		_step_dive(delta)
		return

	var goal = null
	if stun_time <= 0.0:
		goal = _resolve_goal(delta)

	var desired_speed := 0.0
	if goal != null:
		var to_target: Vector3 = goal["pos"] - position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance > 0.05:
			var direction := to_target / distance
			# L'inertie limite la vitesse de rotation : plus on va vite, moins on tourne.
			var turn_rate := lerpf(TURN_RATE_STILL, TURN_RATE_FAST, clampf(speed / top_speed(), 0.0, 1.0))
			var angle := heading.signed_angle_to(direction, Vector3.UP)
			var turn := clampf(angle, -turn_rate * delta, turn_rate * delta)
			heading = heading.rotated(Vector3.UP, turn).normalized()

			desired_speed = ALLURE_SPEED[goal["allure"]] * speed_factor()
			# Virage serré : on ralentit tant que le joueur n'est pas aligné.
			var misalignment := absf(angle)
			if misalignment > 0.5:
				var cap := lerpf(4.5, 1.0, clampf((misalignment - 0.5) / 1.5, 0.0, 1.0))
				desired_speed = minf(desired_speed, cap)
			# Dernier point : on freine pour s'arrêter dessus.
			if goal["final"]:
				desired_speed = minf(desired_speed, sqrt(2.0 * DECEL * 0.8 * distance))

	if speed < desired_speed:
		speed = minf(desired_speed, speed + ACCEL * delta)
	else:
		speed = maxf(desired_speed, speed - DECEL * delta)

	position += heading * speed * delta
	position.y = 0.0
	rotation.y = atan2(heading.x, heading.z)
	_update_stamina(delta)

	if director != null and director.ball.holder == self:
		if speed > 0.4:
			touch_timer -= delta
			if touch_timer <= 0.0:
				touch_timer = TOUCH_INTERVAL
				director.dribble_touch(self)
		else:
			director.hold_ball(self)


## Choisit l'objectif du moment : premier ordre de la file, sinon objectif de l'IA.
func _resolve_goal(delta: float):
	while not orders.is_empty():
		var order: Dictionary = orders[0]
		match order["type"]:
			"move":
				if _flat_distance_to(order["pos"]) < REACH_RADIUS:
					_pop_order()
					continue
				wait_time = 0.0
				var next_is_move: bool = orders.size() > 1 and orders[1]["type"] == "move"
				return {"pos": order["pos"], "allure": order["allure"], "final": not next_is_move}
			"tackle":
				var target = order["target"]
				wait_time += delta
				if not is_instance_valid(target) or director.ball.holder != target or wait_time > 6.0:
					_pop_order()
					continue
				if _flat_distance_to(target.position) <= TACKLE_RANGE:
					director.do_tackle(self, target)
					_pop_order()
					continue
				var far := _flat_distance_to(target.position) > 4.0
				return {"pos": target.position, "allure": Allure.SPRINT if far else Allure.TROT, "final": false}
			_:
				# Passe ou tir : il faut avoir le ballon pour l'exécuter.
				if director.ball.holder == self:
					var done: Dictionary = order
					_pop_order()
					director.execute_action(self, done)
					continue
				wait_time += delta
				if wait_time > ORDER_TIMEOUT:
					_pop_order()
					continue
				return null
	return ai_goal


func _pop_order() -> void:
	orders.pop_front()
	wait_time = 0.0
	orders_changed.emit()


func _update_stamina(delta: float) -> void:
	var ratio := speed / 8.0
	if speed > 2.5:
		stamina -= 0.18 * ratio * ratio * delta * 100.0 / (60.0 + float(stats["endurance"]))
	elif speed < 1.0:
		stamina += 0.05 * delta
	stamina = clampf(stamina, 0.0, 100.0)


func start_dive(target_z: float, duration: float) -> void:
	var to := Vector3(position.x, 0.0, target_z)
	dive = {"from": position, "to": to, "t": 0.0, "dur": maxf(duration, 0.2)}


func _step_dive(delta: float) -> void:
	dive["t"] = float(dive["t"]) + delta
	var k := clampf(float(dive["t"]) / float(dive["dur"]), 0.0, 1.0)
	var from: Vector3 = dive["from"]
	var to: Vector3 = dive["to"]
	position = from.lerp(to, k)
	var sign_z := signf(to.z - from.z)
	_body.rotation.z = sin(k * PI) * 1.1 * sign_z * (-1.0 if team == 0 else 1.0)
	speed = 0.0
	if k >= 1.0:
		dive.clear()
		_body.rotation.z = 0.0
		stun_time = 1.0


func _flat_distance_to(point: Vector3) -> float:
	return Vector2(point.x - position.x, point.z - position.z).length()


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
