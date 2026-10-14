class_name Ball
extends RigidBody3D
## Le ballon : un vrai corps physique, avec effet (courbe) et mémoire du dernier toucheur.

const RADIUS := 0.11
const BALL_MASS := 0.43

## Joueur qui contrôle le ballon (au pied) ou null si le ballon est libre.
var holder: Player = null
var last_toucher: Player = null
var last_touch_team := -1
## Effet : accélération latérale proportionnelle à la vitesse (positif = vers la droite du sens de la balle).
var curve := 0.0
## Incrémenté à chaque frappe : permet aux gardiens de n'évaluer un tir qu'une fois.
var shot_id := 0


func _ready() -> void:
	name = "Ball"
	mass = BALL_MASS
	continuous_cd = true
	linear_damp = 0.03
	angular_damp = 0.3
	var material := PhysicsMaterial.new()
	material.friction = 0.4
	material.bounce = 0.7
	physics_material_override = material

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = RADIUS
	shape.shape = sphere_shape
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS * 1.8  # visuel exagéré pour rester lisible depuis la caméra
	sphere.height = RADIUS * 3.6
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mesh.material_override = mat
	add_child(mesh)


func _physics_process(delta: float) -> void:
	# Le sol freine le ballon qui roule bien plus que l'air ne freine un ballon en vol.
	var on_ground := global_position.y < RADIUS + 0.04
	linear_damp = 0.45 if on_ground else 0.03

	if absf(curve) > 0.001:
		var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		var speed := horizontal.length()
		if speed > 2.0:
			var side := horizontal.normalized().cross(Vector3.UP)
			apply_central_force(side * curve * speed * 0.35 * mass)
		curve *= 1.0 - 0.3 * delta


## Frappe du ballon par un joueur.
func kick(by: Player, velocity: Vector3, p_curve: float) -> void:
	holder = null
	last_toucher = by
	last_touch_team = by.team
	shot_id += 1
	curve = p_curve
	linear_velocity = velocity
	angular_velocity = Vector3(Dice.rng.randf_range(-8.0, 8.0), 0.0, Dice.rng.randf_range(-8.0, 8.0))


## Contact sans frappe voulue (déviation, arrêt repoussé du gardien).
func deflect(by: Player, velocity: Vector3) -> void:
	last_toucher = by
	last_touch_team = by.team
	shot_id += 1
	curve = 0.0
	linear_velocity = velocity
