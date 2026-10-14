class_name Main
extends Node3D
## Scène principale : construit le terrain, les buts, le ballon, les équipes et l'interface,
## gère la pause tactique et la saisie des ordres.

enum Mode { MOVE, PASS, SHOOT, TACKLE }

const PICK_RADIUS := 1.2
## Temps de jeu à attendre après une pause tactique avant d'en refaire une.
const PAUSE_COOLDOWN := 15.0
const TIME_SCALES := [1.0, 2.0, 4.0]
const LINE_WIDTH := 0.12
const ALLURE_COLORS := {
	Player.Allure.MARCHE: Color(0.45, 0.82, 1.0),
	Player.Allure.TROT: Color(1.0, 0.85, 0.25),
	Player.Allure.SPRINT: Color(1.0, 0.4, 0.25),
}
const PASS_COLOR := Color(0.35, 0.95, 0.9)
const SHOT_COLOR := Color(1.0, 0.6, 0.15)
const TACKLE_COLOR := Color(1.0, 0.3, 0.3)

var ball: Ball
var director: MatchDirector
var ui: GameUI
var camera: Camera3D
var selected: Player = null
var mode := Mode.MOVE
var current_allure: int = Player.Allure.TROT
var opt_aerial := false
var opt_pass_power := 1.0  # multiplicateur de la force de passe
var opt_shot_power := 0.8  # puissance de frappe 0.3 - 1.0
var opt_height := 1  # 0 ras du sol, 1 mi-hauteur, 2 lucarne
var opt_curve := 0  # effet, de -4 à 4
var paused := false
var pause_kind := "tactical"  # "tactical" (avec cooldown) ou "dead_ball" (offerte)
var frozen := false
var pause_cooldown_left := 0.0
var time_scale_index := 0
var hover_ground = null  # Vector3 ou null

var _world: Node3D
var _overlay: ImmediateMesh
var _ball_marker: MeshInstance3D
var _tri_pos := PackedVector3Array()
var _tri_col := PackedColorArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # l'interface reste active pendant la pause
	_world = Node3D.new()
	_world.name = "World"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE  # physique et joueurs s'arrêtent en pause
	add_child(_world)

	_build_environment()
	_build_field()
	_build_goals()
	ball = Ball.new()
	_world.add_child(ball)
	ball.position = Vector3(0.0, Ball.RADIUS, 0.0)

	director = MatchDirector.new()
	director.name = "Director"
	_world.add_child(director)
	director.setup(_world, ball)

	_build_camera()
	_build_overlay()
	_build_ball_marker()

	ui = GameUI.new()
	add_child(ui)
	ui.setup(self)

	director.event_logged.connect(ui.add_event)
	director.banner_requested.connect(ui.show_banner)
	director.dead_ball_pause_requested.connect(_on_dead_ball_pause)
	director.ball_stopped.connect(_on_dead_ball_pause)
	director.freeze_requested.connect(_on_freeze)
	director.full_time.connect(ui.show_end)

	select_player(director.player_at(0, 3))
	director.begin_kickoff(0)


func _process(delta: float) -> void:
	director.tick_realtime(delta)
	if not paused and not frozen and pause_cooldown_left > 0.0:
		pause_cooldown_left = maxf(0.0, pause_cooldown_left - delta)
	hover_ground = _screen_to_ground(get_viewport().get_mouse_position())
	_ball_marker.position = Vector3(ball.global_position.x, 0.05, ball.global_position.z)
	_redraw_overlay()
	ui.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				toggle_pause()
			KEY_ESCAPE:
				set_mode(Mode.MOVE)
			KEY_1:
				set_allure(Player.Allure.MARCHE)
			KEY_2:
				set_allure(Player.Allure.TROT)
			KEY_3:
				set_allure(Player.Allure.SPRINT)
			KEY_T:
				cycle_time_scale()
			KEY_P:
				director.auto_pause_enabled = not director.auto_pause_enabled
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_on_left_click(event.position)
			MOUSE_BUTTON_RIGHT:
				if can_give_orders():
					clear_selected_orders()
			MOUSE_BUTTON_WHEEL_UP:
				adjust_curve(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				adjust_curve(-1)


# --- Pause et temps -------------------------------------------------------------------------

func can_give_orders() -> bool:
	return paused and director.phase == MatchDirector.Phase.LIVE


## Bascule la pause tactique. Reprendre après une pause tactique démarre le cooldown.
func toggle_pause() -> void:
	if director.phase != MatchDirector.Phase.LIVE:
		return
	if paused:
		set_paused(false)
		if pause_kind == "tactical":
			pause_cooldown_left = PAUSE_COOLDOWN
	elif pause_cooldown_left <= 0.0:
		pause_kind = "tactical"
		set_paused(true)


func set_paused(value: bool) -> void:
	paused = value
	_apply_tree_pause()


func _apply_tree_pause() -> void:
	get_tree().paused = paused or frozen


func _on_dead_ball_pause() -> void:
	pause_kind = "dead_ball"
	set_mode(Mode.MOVE)
	set_paused(true)


func _on_freeze(value: bool) -> void:
	frozen = value
	_apply_tree_pause()


func cycle_time_scale() -> void:
	time_scale_index = (time_scale_index + 1) % TIME_SCALES.size()
	Engine.time_scale = TIME_SCALES[time_scale_index]


func restart_match() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


# --- Réglages d'ordres ----------------------------------------------------------------------

func set_mode(value: Mode) -> void:
	mode = value


func set_allure(value: int) -> void:
	current_allure = value
	mode = Mode.MOVE


func adjust_curve(step: int) -> void:
	if mode == Mode.PASS or mode == Mode.SHOOT:
		opt_curve = clampi(opt_curve + step, -4, 4)


func clear_selected_orders() -> void:
	if selected != null:
		selected.clear_orders()


func select_player(player: Player) -> void:
	if player != null and player.is_keeper:
		return
	if selected != null:
		selected.set_selected(false)
	selected = player
	if selected != null:
		selected.set_selected(true)


## Effet réellement appliqué (limité par la technique du joueur sélectionné).
func effective_curve() -> float:
	if selected == null:
		return 0.0
	return float(opt_curve) / 4.0 * Rules.max_curve(selected)


# --- Saisie ---------------------------------------------------------------------------------

func _on_left_click(screen_pos: Vector2) -> void:
	if not can_give_orders():
		return
	var ground = _screen_to_ground(screen_pos)
	if ground == null:
		return
	var clicked := _player_near(ground)
	match mode:
		Mode.MOVE:
			if clicked != null and clicked.team == 0:
				select_player(clicked)
			elif selected != null:
				selected.add_order(ground, current_allure)
		Mode.PASS:
			if selected == null:
				return
			var order := {"type": "pass", "aerial": opt_aerial, "power": opt_pass_power, "curve": float(opt_curve) / 4.0}
			if clicked != null and clicked.team == 0 and clicked != selected:
				order["target"] = clicked
			else:
				order["pos"] = Vector3(ground.x, 0.0, ground.z)
			selected.add_action_order(order)
			mode = Mode.MOVE
		Mode.SHOOT:
			if selected == null:
				return
			selected.add_action_order({
				"type": "shoot",
				"z": shot_aim_z(ground),
				"height": opt_height,
				"power": opt_shot_power,
				"curve": float(opt_curve) / 4.0,
			})
			mode = Mode.MOVE
		Mode.TACKLE:
			if selected != null and clicked != null and clicked.team == 1:
				selected.add_action_order({"type": "tackle", "target": clicked})
				mode = Mode.MOVE


## Latéral visé dans le but : clic près du but = clic dans le but, sinon projection depuis le joueur.
func shot_aim_z(ground: Vector3) -> float:
	var goal_x := Rules.goal_x(0)
	if absf(ground.x - goal_x) < 6.0:
		return ground.z
	var origin := selected.planned_position()
	var run := ground.x - origin.x
	if absf(run) < 0.5 or signf(run) != signf(goal_x - origin.x):
		return ground.z
	return origin.z + (ground.z - origin.z) * (goal_x - origin.x) / run


func _screen_to_ground(screen_pos: Vector2):
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)


func _player_near(point: Vector3) -> Player:
	var best: Player = null
	var best_distance := PICK_RADIUS
	for player in director.players:
		var distance := Vector2(player.position.x - point.x, player.position.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


## Aperçu du résultat de l'ordre en cours de visée (pour l'infobulle de l'interface).
func compute_preview() -> Dictionary:
	if not can_give_orders() or selected == null or hover_ground == null:
		return {}
	var hover: Vector3 = hover_ground
	var origin := selected.planned_position()
	var clicked := _player_near(hover)
	var pressure := Rules.pressure_at(origin, 0, director.players)
	var title := ""
	var chance := 0.0
	var warning := ""
	match mode:
		Mode.PASS:
			var target_pos := hover
			title = "Passe vers un point"
			if clicked != null and clicked.team == 0 and clicked != selected:
				target_pos = clicked.position
				title = "Passe vers N°%d %s" % [clicked.number, clicked.display_name]
			var distance := Rules.horizontal_distance(origin, target_pos)
			chance = Rules.pass_chance(selected, distance, opt_aerial, pressure, effective_curve())
			if not opt_aerial and _opponent_on_segment(origin, target_pos):
				warning = "Un adversaire coupe la trajectoire"
		Mode.SHOOT:
			var target := Vector3(Rules.goal_x(0), 0.0, clampf(shot_aim_z(hover), -3.4, 3.4))
			title = "Tir : %s" % String(Rules.SHOT_HEIGHT_NAMES[opt_height]).to_lower()
			var distance := Rules.horizontal_distance(origin, target)
			chance = Rules.shot_chance(selected, distance, opt_height, opt_shot_power, pressure, effective_curve())
			if distance > 28.0:
				warning = "Trop loin pour cadrer un tir"
		Mode.TACKLE:
			if clicked == null or clicked.team != 1:
				return {}
			title = "Tacle sur N°%d" % clicked.number
			chance = Rules.tackle_chance(selected, clicked)
		_:
			return {}
	chance = clampf(chance, 1.0, 99.0)
	return {
		"title": title,
		"chance": chance,
		"crit_success": floorf(chance / 10.0),
		"crit_fail": maxf(0.0, 50.0 - chance),
		"warning": warning,
	}


func _opponent_on_segment(a: Vector3, b: Vector3) -> bool:
	return Rules.lane_blocked(a, b, 0, director.players, 1.6)


# --- Construction de la scène ---------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.68)
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
	box.size = Vector3(Rules.HALF_LENGTH * 2.0 + 30.0, 0.2, Rules.HALF_WIDTH * 2.0 + 30.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.1, 0.0)
	ground.add_child(shape)

	var surround := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(Rules.HALF_LENGTH * 2.0 + 30.0, Rules.HALF_WIDTH * 2.0 + 30.0)
	surround.mesh = plane
	surround.material_override = _flat_material(Color(0.1, 0.22, 0.13))
	surround.position.y = -0.02
	ground.add_child(surround)

	# Bandes de tonte en alternance.
	var stripes := 10
	var stripe_length := Rules.HALF_LENGTH * 2.0 / stripes
	for i in stripes:
		var stripe := MeshInstance3D.new()
		var stripe_mesh := PlaneMesh.new()
		stripe_mesh.size = Vector2(stripe_length, Rules.HALF_WIDTH * 2.0)
		stripe.mesh = stripe_mesh
		stripe.material_override = _flat_material(Color(0.2, 0.5, 0.24) if i % 2 == 0 else Color(0.17, 0.45, 0.21))
		stripe.position = Vector3(-Rules.HALF_LENGTH + stripe_length * (i + 0.5), 0.0, 0.0)
		ground.add_child(stripe)
	_world.add_child(ground)

	var hl := Rules.HALF_LENGTH
	var hw := Rules.HALF_WIDTH
	_add_line(Vector3(0.0, 0.0, -hw), Vector3(hl * 2.0, LINE_WIDTH, LINE_WIDTH))
	_add_line(Vector3(0.0, 0.0, hw), Vector3(hl * 2.0, LINE_WIDTH, LINE_WIDTH))
	_add_line(Vector3(-hl, 0.0, 0.0), Vector3(LINE_WIDTH, LINE_WIDTH, hw * 2.0))
	_add_line(Vector3(hl, 0.0, 0.0), Vector3(LINE_WIDTH, LINE_WIDTH, hw * 2.0))
	_add_line(Vector3.ZERO, Vector3(LINE_WIDTH, LINE_WIDTH, hw * 2.0))
	for side in [-1.0, 1.0]:
		# Surface de réparation et rond central (en rectangle/anneau simplifié).
		_add_line(Vector3(side * (hl - 8.0), 0.0, 0.0), Vector3(LINE_WIDTH, LINE_WIDTH, 16.0))
		_add_line(Vector3(side * (hl - 4.0), 0.0, -8.0), Vector3(8.0, LINE_WIDTH, LINE_WIDTH))
		_add_line(Vector3(side * (hl - 4.0), 0.0, 8.0), Vector3(8.0, LINE_WIDTH, LINE_WIDTH))
	var circle_segments := 32
	for i in circle_segments:
		var angle := TAU * float(i) / float(circle_segments)
		var dot := MeshInstance3D.new()
		var dot_mesh := BoxMesh.new()
		dot_mesh.size = Vector3(0.6, LINE_WIDTH, LINE_WIDTH)
		dot.mesh = dot_mesh
		dot.material_override = _flat_material(Color(0.95, 0.95, 0.95))
		dot.position = Vector3(cos(angle) * 5.0, 0.01, sin(angle) * 5.0)
		dot.rotation.y = -angle + PI / 2.0
		_world.add_child(dot)


func _add_line(pos: Vector3, size: Vector3) -> void:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	line.mesh = box
	line.material_override = _flat_material(Color(0.95, 0.95, 0.95))
	line.position = pos + Vector3(0.0, 0.01, 0.0)
	_world.add_child(line)


func _build_goals() -> void:
	var net_material := StandardMaterial3D.new()
	net_material.albedo_color = Color(1.0, 1.0, 1.0, 0.16)
	net_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	net_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame_material := _flat_material(Color(0.97, 0.97, 0.97))
	var net_physics := PhysicsMaterial.new()
	net_physics.bounce = 0.1
	net_physics.friction = 0.6
	var half := Rules.GOAL_HALF_WIDTH
	var height := Rules.GOAL_HEIGHT
	var depth := Rules.GOAL_DEPTH

	for side in [-1.0, 1.0]:
		var x0: float = side * Rules.HALF_LENGTH
		var frame := StaticBody3D.new()
		frame.name = "Goal%s" % ("Right" if side > 0.0 else "Left")
		frame.physics_material_override = net_physics
		_world.add_child(frame)

		for z in [-half, half]:
			_add_cylinder(frame, Vector3(x0, height / 2.0, z), Vector3.ZERO, 0.06, height, frame_material)
		_add_cylinder(frame, Vector3(x0, height, 0.0), Vector3(90.0, 0.0, 0.0), 0.06, half * 2.0, frame_material)

		# Filets : collisions simples (le ballon s'y arrête) + voiles translucides.
		_add_net_panel(frame, Vector3(x0 + side * depth, height / 2.0, 0.0), Vector3(0.1, height, half * 2.0), net_material)
		_add_net_panel(frame, Vector3(x0 + side * depth / 2.0, height / 2.0, -half), Vector3(depth, height, 0.1), net_material)
		_add_net_panel(frame, Vector3(x0 + side * depth / 2.0, height / 2.0, half), Vector3(depth, height, 0.1), net_material)
		_add_net_panel(frame, Vector3(x0 + side * depth / 2.0, height, 0.0), Vector3(depth, 0.1, half * 2.0), net_material)


func _add_cylinder(body: StaticBody3D, pos: Vector3, rot_deg: Vector3, radius: float, length: float, material: Material) -> void:
	var shape := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = length
	shape.shape = cylinder_shape
	shape.position = pos
	shape.rotation_degrees = rot_deg
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = length
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = pos
	mesh.rotation_degrees = rot_deg
	body.add_child(mesh)


func _add_net_panel(body: StaticBody3D, pos: Vector3, size: Vector3, material: Material) -> void:
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = pos
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = pos
	body.add_child(mesh)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	_world.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 56.0, 30.0), Vector3(0.0, 0.0, 2.0))
	camera.current = true


func _build_overlay() -> void:
	_overlay = ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = _overlay
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	instance.material_override = material
	_world.add_child(instance)


func _build_ball_marker() -> void:
	# Le ballon est minuscule vu de haut : un anneau au sol permet de le repérer.
	_ball_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.58
	_ball_marker.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ball_marker.material_override = material
	_world.add_child(_ball_marker)


# --- Tracés 3D des ordres -------------------------------------------------------------------

func _redraw_overlay() -> void:
	_overlay.clear_surfaces()
	_tri_pos.clear()
	_tri_col.clear()

	for player in director.players:
		if player.team != 0 or player.orders.is_empty():
			continue
		var strong := player == selected
		var alpha := 0.95 if strong else 0.5
		var at := player.position
		for order in player.orders:
			match order["type"]:
				"move":
					var color: Color = ALLURE_COLORS[order["allure"]]
					color.a = alpha
					_ribbon(at, order["pos"], 0.2, color)
					_diamond(order["pos"], 0.45, color)
					at = order["pos"]
				"pass":
					var end := _order_end(order, at)
					var color := PASS_COLOR
					color.a = alpha
					_ribbon(at, end, 0.14, color)
					_diamond(end, 0.5, color)
				"shoot":
					var end := Vector3(Rules.goal_x(0), 0.0, clampf(float(order["z"]), -3.4, 3.4))
					var color := SHOT_COLOR
					color.a = alpha
					_ribbon(at, end, 0.18, color)
					_diamond(end, 0.5, color)
				"tackle":
					var target = order["target"]
					if is_instance_valid(target):
						var color := TACKLE_COLOR
						color.a = alpha
						_ribbon(at, target.position, 0.14, color)
						_diamond(target.position, 0.5, color)

	if selected != null and paused:
		_ring(selected.position, selected.control_radius(), 0.08, Color(1.0, 1.0, 1.0, 0.35))
		if can_give_orders() and hover_ground != null:
			var hover: Vector3 = hover_ground
			var origin := selected.planned_position()
			var preview_color := Color(1.0, 1.0, 1.0, 0.4)
			match mode:
				Mode.MOVE:
					preview_color = ALLURE_COLORS[current_allure]
					preview_color.a = 0.4
				Mode.PASS:
					preview_color = PASS_COLOR
					preview_color.a = 0.5
				Mode.SHOOT:
					preview_color = SHOT_COLOR
					preview_color.a = 0.5
					_ribbon(Vector3(Rules.goal_x(0), 0.0, -Rules.GOAL_HALF_WIDTH), Vector3(Rules.goal_x(0), 0.0, Rules.GOAL_HALF_WIDTH), 0.5, Color(1.0, 0.85, 0.2, 0.35))
					hover = Vector3(Rules.goal_x(0), 0.0, clampf(shot_aim_z(hover), -3.4, 3.4))
				Mode.TACKLE:
					preview_color = TACKLE_COLOR
					preview_color.a = 0.5
			_ribbon(origin, hover, 0.1, preview_color)

	if not _tri_pos.is_empty():
		_overlay.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in _tri_pos.size():
			_overlay.surface_set_color(_tri_col[i])
			_overlay.surface_add_vertex(_tri_pos[i])
		_overlay.surface_end()


func _order_end(order: Dictionary, from: Vector3) -> Vector3:
	var target = order.get("target")
	if target != null and is_instance_valid(target):
		return target.position
	return order["pos"]


func _ribbon(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if flat.length() < 0.01:
		return
	var side := flat.normalized().cross(Vector3.UP) * width * 0.5
	var y := 0.07
	var a0 := Vector3(a.x, y, a.z) + side
	var a1 := Vector3(a.x, y, a.z) - side
	var b0 := Vector3(b.x, y, b.z) + side
	var b1 := Vector3(b.x, y, b.z) - side
	for v in [a0, a1, b1, a0, b1, b0]:
		_tri_pos.append(v)
		_tri_col.append(color)


func _diamond(center: Vector3, radius: float, color: Color) -> void:
	var y := 0.08
	var top := Vector3(center.x, y, center.z - radius)
	var bottom := Vector3(center.x, y, center.z + radius)
	var left := Vector3(center.x - radius, y, center.z)
	var right := Vector3(center.x + radius, y, center.z)
	for v in [top, left, right, left, bottom, right]:
		_tri_pos.append(v)
		_tri_col.append(color)


func _ring(center: Vector3, radius: float, width: float, color: Color) -> void:
	var segments := 32
	var previous := center + Vector3(radius, 0.0, 0.0)
	for i in range(1, segments + 1):
		var angle := TAU * float(i) / float(segments)
		var point := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_ribbon(previous, point, width, color)
		previous = point


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
