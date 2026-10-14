extends Node3D
## Scène principale du prototype : terrain, ballon physique, 5 contre 5, pause tactique et ordres.

const FIELD_LENGTH := 60.0
const FIELD_WIDTH := 40.0
const BALL_RADIUS := 0.11
const BALL_MASS := 0.43
const LINE_WIDTH := 0.12
## Temps (en secondes de jeu) à attendre après une pause avant de pouvoir en refaire une.
const PAUSE_COOLDOWN := 15.0
const PICK_RADIUS := 1.2

const TEAM_COLORS := [Color(0.2, 0.45, 0.95), Color(0.9, 0.25, 0.25)]
const ALLURE_COLORS := {
	Player.Allure.MARCHE: Color(0.4, 0.8, 1.0),
	Player.Allure.TROT: Color(1.0, 0.85, 0.2),
	Player.Allure.SPRINT: Color(1.0, 0.35, 0.2),
}
const ALLURE_NAMES := {
	Player.Allure.MARCHE: "marche",
	Player.Allure.TROT: "trot",
	Player.Allure.SPRINT: "sprint",
}
## Positions de départ (équipe 0, qui défend à gauche) : gardien puis 4 joueurs de champ.
const FORMATION := [
	Vector3(-27.0, 0.0, 0.0),
	Vector3(-13.0, 0.0, -8.0),
	Vector3(-13.0, 0.0, 8.0),
	Vector3(-5.0, 0.0, -5.0),
	Vector3(-5.0, 0.0, 5.0),
]

var ball: RigidBody3D
var players: Array[Player] = []
var selected: Player = null
var current_allure: int = Player.Allure.TROT
var paused := false
var pause_cooldown_left := 0.0

var _world: Node3D
var _camera: Camera3D
var _hud: Label
var _path_mesh: ImmediateMesh


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # l'interface reste active pendant la pause
	_world = Node3D.new()
	_world.name = "World"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE  # la physique et les joueurs s'arrêtent en pause
	add_child(_world)

	_build_environment()
	_build_field()
	_build_ball()
	_build_players()
	_build_camera()
	_build_path_overlay()
	_build_hud()


func _process(delta: float) -> void:
	if not paused and pause_cooldown_left > 0.0:
		pause_cooldown_left = maxf(0.0, pause_cooldown_left - delta)
	_redraw_paths()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				toggle_pause()
			KEY_1:
				current_allure = Player.Allure.MARCHE
			KEY_2:
				current_allure = Player.Allure.TROT
			KEY_3:
				current_allure = Player.Allure.SPRINT
			KEY_K:
				kick()
			KEY_R:
				reset_ball()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and paused and selected != null:
			selected.clear_orders()


## Bascule la pause tactique. Reprendre le jeu déclenche le cooldown avant la prochaine pause.
func toggle_pause() -> void:
	if paused:
		set_paused(false)
		pause_cooldown_left = PAUSE_COOLDOWN
	elif pause_cooldown_left <= 0.0:
		set_paused(true)


func set_paused(value: bool) -> void:
	paused = value
	get_tree().paused = value


func kick() -> void:
	ball.linear_velocity = Vector3(18.0, 6.0, 3.0)


func reset_ball() -> void:
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = Vector3(0.0, BALL_RADIUS, 0.0)


func select_player(player: Player) -> void:
	if selected != null:
		selected.set_selected(false)
	selected = player
	if selected != null:
		selected.set_selected(true)


func _on_left_click(screen_pos: Vector2) -> void:
	var ground = _screen_to_ground(screen_pos)
	if ground == null:
		return
	var clicked := _player_near(ground)
	if clicked != null and clicked.team == 0:
		select_player(clicked)
	elif paused and selected != null:
		selected.add_order(ground, current_allure)


func _screen_to_ground(screen_pos: Vector2):
	var origin := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)


func _player_near(point: Vector3) -> Player:
	var best: Player = null
	var best_distance := PICK_RADIUS
	for player in players:
		var distance := Vector2(player.position.x - point.x, player.position.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
	_world.add_child(sun)


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
	_world.add_child(ground)

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
	_world.add_child(line)


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
	_world.add_child(ball)


func _build_players() -> void:
	for team in 2:
		for i in FORMATION.size():
			var player := Player.new()
			player.name = "Team%d_Player%d" % [team, i]
			_world.add_child(player)
			player.setup(team, i == 0, TEAM_COLORS[team])
			var spawn: Vector3 = FORMATION[i]
			player.position = spawn if team == 0 else Vector3(-spawn.x, 0.0, spawn.z)
			players.append(player)
	select_player(players[3])


func _build_camera() -> void:
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.look_at_from_position(Vector3(0.0, 45.0, 28.0), Vector3.ZERO)
	_camera.current = true


func _build_path_overlay() -> void:
	_path_mesh = ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = _path_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	instance.material_override = material
	_world.add_child(instance)


func _redraw_paths() -> void:
	_path_mesh.clear_surfaces()
	var drew_something := false
	for player in players:
		if player.team != 0 or player.orders.is_empty():
			continue
		if not drew_something:
			_path_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			drew_something = true
		var from := player.position + Vector3(0.0, 0.08, 0.0)
		for order in player.orders:
			var to: Vector3 = order["pos"] + Vector3(0.0, 0.08, 0.0)
			var color: Color = ALLURE_COLORS[order["allure"]]
			_path_mesh.surface_set_color(color)
			_path_mesh.surface_add_vertex(from)
			_path_mesh.surface_set_color(color)
			_path_mesh.surface_add_vertex(to)
			# Croix qui marque le point de passage.
			for offset in [Vector3(0.4, 0.0, 0.0), Vector3(0.0, 0.0, 0.4)]:
				_path_mesh.surface_set_color(color)
				_path_mesh.surface_add_vertex(to - offset)
				_path_mesh.surface_set_color(color)
				_path_mesh.surface_add_vertex(to + offset)
			from = to
	if drew_something:
		_path_mesh.surface_end()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16.0, 12.0)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_hud)
	add_child(layer)


func _update_hud() -> void:
	var state := "PAUSE TACTIQUE : donne tes ordres" if paused else "Match en cours"
	var cooldown := ""
	if not paused:
		if pause_cooldown_left > 0.0:
			cooldown = "  (prochaine pause dans %.0f s)" % pause_cooldown_left
		else:
			cooldown = "  (pause disponible)"
	_hud.text = "%s%s\nAllure : %s\n\nEspace : pause / reprise   |   1 2 3 : marche, trot, sprint\nClic gauche : choisir un joueur bleu, ou ajouter un point de passage (en pause)\nClic droit : effacer les ordres du joueur choisi   |   K : frappe test   |   R : ballon au centre" % [
		state, cooldown, ALLURE_NAMES[current_allure]
	]


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
