extends Node3D
## Scène principale du prototype : terrain, ballon physique, caméra vue du dessus.

const FIELD_LENGTH := 60.0
const FIELD_WIDTH := 40.0
const BALL_RADIUS := 0.11
const BALL_MASS := 0.43
const LINE_WIDTH := 0.12

var ball: RigidBody3D


func _ready() -> void:
	_build_environment()
	_build_field()
	_build_ball()
	_build_camera()
	_build_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			kick()
		elif event.keycode == KEY_R:
			reset_ball()


func kick() -> void:
	ball.linear_velocity = Vector3(18.0, 6.0, 3.0)


func reset_ball() -> void:
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = Vector3(0.0, BALL_RADIUS, 0.0)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	add_child(sun)


func _build_field() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var material := PhysicsMaterial.new()
	material.friction = 0.8
	material.bounce = 0.5
	ground.physics_material_override = material

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FIELD_LENGTH + 20.0, 0.2, FIELD_WIDTH + 20.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.1, 0.0)
	ground.add_child(shape)

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_LENGTH + 20.0, FIELD_WIDTH + 20.0)
	mesh.mesh = plane
	mesh.material_override = _flat_material(Color(0.18, 0.45, 0.2))
	ground.add_child(mesh)
	add_child(ground)

	var half_l := FIELD_LENGTH / 2.0
	var half_w := FIELD_WIDTH / 2.0
	_add_line(Vector3(0.0, 0.0, -half_w), Vector3(FIELD_LENGTH, LINE_WIDTH, LINE_WIDTH))
	_add_line(Vector3(0.0, 0.0, half_w), Vector3(FIELD_LENGTH, LINE_WIDTH, LINE_WIDTH))
	_add_line(Vector3(-half_l, 0.0, 0.0), Vector3(LINE_WIDTH, LINE_WIDTH, FIELD_WIDTH))
	_add_line(Vector3(half_l, 0.0, 0.0), Vector3(LINE_WIDTH, LINE_WIDTH, FIELD_WIDTH))
	_add_line(Vector3.ZERO, Vector3(LINE_WIDTH, LINE_WIDTH, FIELD_WIDTH))


func _add_line(pos: Vector3, size: Vector3) -> void:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	line.mesh = box
	line.material_override = _flat_material(Color(0.95, 0.95, 0.95))
	line.position = pos + Vector3(0.0, 0.01, 0.0)
	add_child(line)


func _build_ball() -> void:
	ball = RigidBody3D.new()
	ball.name = "Ball"
	ball.mass = BALL_MASS
	ball.continuous_cd = true
	ball.linear_damp = 0.05
	ball.angular_damp = 0.3
	var material := PhysicsMaterial.new()
	material.friction = 0.4
	material.bounce = 0.7
	ball.physics_material_override = material

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = BALL_RADIUS
	shape.shape = sphere_shape
	ball.add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	mesh.mesh = sphere
	mesh.material_override = _flat_material(Color(1.0, 1.0, 1.0))
	ball.add_child(mesh)

	ball.position = Vector3(0.0, BALL_RADIUS, 0.0)
	add_child(ball)


func _build_camera() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 45.0, 28.0), Vector3.ZERO)
	camera.current = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "Espace : frappe  |  R : remettre le ballon au centre"
	label.position = Vector2(16.0, 12.0)
	layer.add_child(label)
	add_child(layer)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
