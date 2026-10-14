class_name MatchDirector
extends Node
## Chef d'orchestre du match : possession, passes, tirs, tacles, gardiens, buts, sorties de balle,
## mi-temps et IA des joueurs sans ordre.

signal event_logged(text: String, kind: String)  # kind : "dice", "info", "goal"
signal banner_requested(title: String, subtitle: String)
signal dead_ball_pause_requested
signal freeze_requested(frozen: bool)
signal full_time
signal ball_stopped

enum Phase { LIVE, GOAL, HALF_TIME, FULL_TIME }

const HALF_DURATION := 300.0  # 5 minutes par mi-temps
const AI_INTERVAL := 0.15
## Un joueur de l'équipe pilotée garde le ballon ce temps sans ordre avant de jouer seul.
const HUMAN_CARRIER_PATIENCE := 3.0
## Positions de départ (équipe 0, qui défend à gauche) : gardien, 2 défenseurs, 2 attaquants.
const FORMATION := [
	Vector3(-27.0, 0.0, 0.0),
	Vector3(-14.0, 0.0, -8.0),
	Vector3(-14.0, 0.0, 8.0),
	Vector3(-4.0, 0.0, -6.0),
	Vector3(-4.0, 0.0, 6.0),
]
const ROLES := ["GK", "DEF", "DEF", "ATT", "ATT"]
const NAMES := [
	["Lambert", "Moreau", "Girard", "Fontaine", "Marchand"],
	["Roussel", "Perrin", "Colin", "Dupuis", "Benoit"],
]
const TEAM_NAMES := ["BLEUS", "ROUGES"]
const TEAM_COLORS := [Color(0.2, 0.45, 0.95), Color(0.9, 0.25, 0.25)]

var ball: Ball
var players: Array[Player] = []
var score := [0, 0]
var clock := 0.0
var half := 1
var phase := Phase.LIVE
var possession_team := -1
var ai_enabled := true
## Équipe pilotée par le joueur (-1 : aucune, tout est géré par l'IA).
var human_team := 0
## Pause offerte dès que le ballon est à l'arrêt (réglable).
var auto_pause_enabled := true

var _world: Node3D
var _dead_timer := 0.0
var _ai_timer := 0.0
var _next_kickoff_team := 0
var _ball_still_time := 0.0
var _auto_pause_armed := false


func setup(world: Node3D, p_ball: Ball) -> void:
	_world = world
	ball = p_ball
	for team in 2:
		var stat_rng := RandomNumberGenerator.new()
		stat_rng.seed = 1000 + team
		for i in FORMATION.size():
			var player := Player.new()
			player.name = "Team%d_Player%d" % [team, i]
			player.director = self
			world.add_child(player)
			player.setup(team, ROLES[i], TEAM_COLORS[team], NAMES[team][i], i + 1)
			_roll_stats(player, stat_rng)
			players.append(player)


func _roll_stats(player: Player, stat_rng: RandomNumberGenerator) -> void:
	var base := {}
	match player.role:
		"GK":
			base = {"vitesse": 55, "endurance": 65, "force": 60, "agilite": 60, "technique": 50, "passe": 55, "frappe": 50, "defense": 40, "tete": 55, "vision": 60, "sang_froid": 65, "reflexes": 72, "placement": 68, "prise": 70}
		"DEF":
			base = {"vitesse": 62, "endurance": 68, "force": 72, "agilite": 58, "technique": 56, "passe": 62, "frappe": 48, "defense": 74, "tete": 70, "vision": 62, "sang_froid": 64, "reflexes": 40, "placement": 40, "prise": 40}
		_:
			base = {"vitesse": 72, "endurance": 66, "force": 58, "agilite": 70, "technique": 72, "passe": 64, "frappe": 72, "defense": 44, "tete": 60, "vision": 66, "sang_froid": 62, "reflexes": 40, "placement": 40, "prise": 40}
	for key in base:
		player.stats[key] = clampi(int(base[key]) + stat_rng.randi_range(-7, 7), 20, 99)


func slot_position(team: int, index: int) -> Vector3:
	var slot: Vector3 = FORMATION[index]
	return slot if team == 0 else Vector3(-slot.x, 0.0, slot.z)


func player_at(team: int, index: int) -> Player:
	return players[team * FORMATION.size() + index]


func opponents_of(player: Player) -> Array:
	return players.filter(func(p): return p.team != player.team)


func teammates_of(player: Player) -> Array:
	return players.filter(func(p): return p.team == player.team and p != player)


func has_ball(player: Player) -> bool:
	return ball.holder == player


func match_clock_text() -> String:
	var total := int(clock)
	return "%02d:%02d" % [total / 60, total % 60]


# --- Boucle de simulation ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if phase != Phase.LIVE:
		return
	clock += delta
	if half == 1 and clock >= HALF_DURATION:
		_end_half()
		return
	if clock >= 2.0 * HALF_DURATION:
		_end_match()
		return
	_check_holder()
	_watch_ball_stopped(delta)
	_update_ball_interactions()
	_update_keepers()
	_check_out_of_play()
	if ai_enabled:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			_ai_timer = AI_INTERVAL
			_run_ai()


## Appelé en temps réel (même pendant les pauses) pour les phases mortes : but, mi-temps.
func tick_realtime(delta: float) -> void:
	if phase == Phase.GOAL or phase == Phase.HALF_TIME:
		_dead_timer -= delta
		if _dead_timer <= 0.0:
			if phase == Phase.HALF_TIME:
				half = 2
			phase = Phase.LIVE
			begin_kickoff(_next_kickoff_team)


## Détecte un ballon à l'arrêt : une seule pause par arrêt. Elle ne se réarme que lorsque
## le ballon a de nouveau bougé, pour ne pas bloquer le jeu en boucle.
func _watch_ball_stopped(delta: float) -> void:
	var speed := ball.linear_velocity.length()
	if speed > 1.5:
		_auto_pause_armed = true
		_ball_still_time = 0.0
	elif speed < 0.4:
		_ball_still_time += delta
		if _auto_pause_armed and _ball_still_time >= 0.4:
			_auto_pause_armed = false
			if auto_pause_enabled:
				event_logged.emit("Ballon arrêté : pause offerte", "info")
				ball_stopped.emit()
	else:
		_ball_still_time = 0.0


# --- Possession ----------------------------------------------------------------------------

func set_holder(player: Player) -> void:
	ball.holder = player
	if player == null:
		return
	ball.last_toucher = player
	ball.last_touch_team = player.team
	ball.curve = 0.0
	ball.linear_velocity *= 0.2
	player.touch_timer = 0.15
	player.contact_lock = 0.0
	player.hold_idle = 0.0
	if player.is_keeper:
		player.decision_timer = 1.2
	if possession_team != -1 and possession_team != player.team:
		_clear_all_orders()
		event_logged.emit("Le ballon change de camp : les ordres sont annulés", "info")
	possession_team = player.team


func _clear_all_orders() -> void:
	for p in players:
		p.clear_orders()


## Le ballon trop loin du porteur est relâché (conduite ratée).
func _check_holder() -> void:
	var holder := ball.holder
	if holder == null:
		return
	var bp := ball.global_position
	var distance := Vector2(bp.x - holder.position.x, bp.z - holder.position.z).length()
	if distance > holder.control_radius() + 0.15 or bp.y > 1.3:
		ball.holder = null
		holder.contact_lock = 0.5
		if holder.team == 0:
			event_logged.emit("N°%d pousse le ballon trop loin" % holder.number, "info")


func dribble_touch(player: Player) -> void:
	var chance := Rules.touch_chance(player, player.speed)
	var result := Dice.resolve(chance)
	var ahead := 0.45 + 0.04 * player.speed
	var extra := 0.0
	var side := 0.0
	match result["tier"]:
		"crit_success":
			ahead -= 0.1
		"fail":
			extra = float(result["margin"]) * 0.03
		"crit_fail":
			extra = 3.0 + Dice.rng.randf() * 2.0
			side = Dice.rng.randf_range(-1.5, 1.5)
	var interval := Player.TOUCH_INTERVAL
	var target := player.position + player.heading * (player.speed * interval + ahead + extra)
	target += player.heading.cross(Vector3.UP) * side
	target.y = Ball.RADIUS
	var velocity := (target - ball.global_position) / interval
	velocity.y = 0.0
	ball.linear_velocity = velocity
	ball.last_toucher = player


func hold_ball(player: Player) -> void:
	var target := player.position + player.heading * 0.6
	target.y = Ball.RADIUS
	var velocity := (target - ball.global_position) * 10.0
	velocity.y = 0.0
	ball.linear_velocity = velocity.limit_length(8.0)


# --- Contacts balle / joueurs --------------------------------------------------------------

func _update_ball_interactions() -> void:
	if ball.holder != null:
		return
	var bp := ball.global_position
	if bp.y > Player.HEIGHT:
		return
	var ball_speed := ball.linear_velocity.length()
	for p in players:
		if p.contact_lock > 0.0 or p.stun_time > 0.0 or not p.dive.is_empty():
			continue
		if p.is_keeper and p.last_eval_shot == ball.shot_id and ball_speed > 5.0:
			continue
		var distance := Vector2(bp.x - p.position.x, bp.z - p.position.z).length()
		if distance > p.control_radius():
			continue
		_try_control(p, ball_speed)
		if ball.holder != null:
			return


func _try_control(player: Player, ball_speed: float) -> void:
	if ball_speed < 2.0:
		set_holder(player)
		return
	var chance := Rules.control_chance(player, ball_speed, ball.global_position.y)
	var result := Dice.resolve(chance)
	player.contact_lock = 0.45
	var notable := ball_speed > 5.0
	if Dice.is_success(result):
		set_holder(player)
		if notable:
			_log_dice("N°%d (%s) contrôle le ballon" % [player.number, TEAM_NAMES[player.team]], result)
		return
	# Contrôle raté : le ballon rebondit sur le joueur, la physique fait le reste.
	var angle := deg_to_rad(Dice.rng.randf_range(40.0, 110.0)) * (1.0 if Dice.rng.randf() < 0.5 else -1.0)
	var factor := 0.45 if result["tier"] == "fail" else 0.8
	var bounce := ball.linear_velocity.rotated(Vector3.UP, angle) * factor
	bounce.y = absf(ball.linear_velocity.y) * 0.3 + 1.0
	ball.deflect(player, bounce)
	if notable:
		_log_dice("N°%d (%s) rate son contrôle" % [player.number, TEAM_NAMES[player.team]], result)


# --- Actions : passe, tir, tacle -----------------------------------------------------------

func execute_action(player: Player, order: Dictionary) -> void:
	match order["type"]:
		"pass":
			do_pass(player, order)
		"shoot":
			do_shoot(player, order)


## Calcule la cible (point au sol) d'une passe, en anticipant la course du receveur.
func pass_target_position(passer_pos: Vector3, order: Dictionary) -> Vector3:
	var target = order.get("target")
	if target != null and is_instance_valid(target):
		var distance := Rules.horizontal_distance(passer_pos, target.position)
		var lead: float = distance / 14.0 * 0.8
		var pos: Vector3 = target.position + target.heading * target.speed * lead
		pos.y = Ball.RADIUS
		return pos
	var point: Vector3 = order["pos"]
	return Vector3(point.x, Ball.RADIUS, point.z)


func do_pass(player: Player, order: Dictionary) -> void:
	var bp := ball.global_position
	var aerial: bool = order.get("aerial", false)
	var power: float = order.get("power", 1.0)
	var curve: float = float(order.get("curve", 0.0)) * Rules.max_curve(player)
	var target_pos := pass_target_position(player.position, order)
	var distance := Rules.horizontal_distance(bp, target_pos)
	var pressure := Rules.pressure_at(player.position, player.team, players)
	var chance := Rules.pass_chance(player, distance, aerial, pressure, curve)
	var result := Dice.resolve(chance)

	var velocity: Vector3
	if aerial:
		velocity = Rules.lob_velocity(bp, target_pos, power)
	else:
		velocity = Rules.flat_pass_velocity(bp, target_pos, power)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	velocity = _rotate_horizontal(velocity, Rules.curve_compensation(curve, distance, horizontal_speed))
	velocity = Rules.apply_error(velocity, result)
	_kick(player, velocity, curve)

	var target = order.get("target")
	var what := "Passe vers N°%d" % target.number if (target != null and is_instance_valid(target)) else "Passe en profondeur"
	if aerial:
		what += " (aérienne)"
	_log_dice("N°%d %s" % [player.number, what], result)


func do_shoot(player: Player, order: Dictionary) -> void:
	var bp := ball.global_position
	var level: int = order.get("height", 1)
	var power: float = order.get("power", 0.8)
	var curve: float = float(order.get("curve", 0.0)) * Rules.max_curve(player)
	var goal_x := Rules.goal_x(player.team)
	var target := Vector3(goal_x, Rules.SHOT_HEIGHTS[level], clampf(float(order["z"]), -3.4, 3.4))
	var distance := Rules.horizontal_distance(bp, target)
	var pressure := Rules.pressure_at(player.position, player.team, players)
	var chance := Rules.shot_chance(player, distance, level, power, pressure, curve)
	var result := Dice.resolve(chance)

	var speed := lerpf(14.0, 32.0, power)
	var velocity := Rules.shot_velocity(bp, target, speed)
	velocity = _rotate_horizontal(velocity, Rules.curve_compensation(curve, distance, speed))
	velocity = Rules.apply_error(velocity, result)
	_kick(player, velocity, curve)
	_log_dice("N°%d (%s) tire — %s" % [player.number, TEAM_NAMES[player.team], String(Rules.SHOT_HEIGHT_NAMES[level]).to_lower()], result)


func do_tackle(tackler: Player, target: Player) -> void:
	if ball.holder != target or tackler.tackle_cooldown > 0.0 or tackler.stun_time > 0.0:
		return
	tackler.tackle_cooldown = 1.2
	var chance := Rules.tackle_chance(tackler, target)
	var result := Dice.resolve(chance)
	var who := "N°%d (%s) tacle N°%d" % [tackler.number, TEAM_NAMES[tackler.team], target.number]
	if Dice.is_success(result):
		target.contact_lock = 0.6
		if result["tier"] == "crit_success":
			target.stun_time = 0.6
		set_holder(tackler)
		_log_dice(who, result)
	else:
		tackler.stun_time = 0.8 if result["tier"] == "fail" else 2.0
		_log_dice(who, result)


func _kick(player: Player, velocity: Vector3, curve: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var dir := flat.normalized() if flat.length() > 0.01 else player.heading
	ball.global_position = Vector3(player.position.x + dir.x * 0.6, maxf(ball.global_position.y, Ball.RADIUS), player.position.z + dir.z * 0.6)
	ball.kick(player, velocity, curve)
	player.contact_lock = 0.5
	player.heading = dir


func _rotate_horizontal(velocity: Vector3, angle: float) -> Vector3:
	var rotated := velocity.rotated(Vector3.UP, angle)
	rotated.y = velocity.y
	return rotated


func _log_dice(text: String, result: Dictionary) -> void:
	event_logged.emit("%s — jet %d / %d : %s" % [text, result["roll"], int(result["chance"]), Dice.label(result)], "dice")


# --- Gardiens -------------------------------------------------------------------------------

func _update_keepers() -> void:
	for keeper in players:
		if not keeper.is_keeper:
			continue
		if not keeper.pending_save.is_empty():
			_apply_pending_save(keeper)
		if ball.holder != null or keeper.last_eval_shot == ball.shot_id:
			continue
		var toward_goal := -1.0 if keeper.team == 0 else 1.0
		var velocity := ball.linear_velocity
		if velocity.x * toward_goal <= 0.0 or velocity.length() < 7.0:
			continue
		if absf(ball.global_position.x - keeper.position.x) > 14.0:
			continue
		keeper.last_eval_shot = ball.shot_id
		_evaluate_save(keeper, velocity)


func _evaluate_save(keeper: Player, velocity: Vector3) -> void:
	var prediction := Rules.predict_plane_crossing(ball.global_position, velocity, keeper.position.x)
	if not prediction["ok"]:
		return
	var y: float = prediction["y"]
	var z: float = prediction["z"]
	if absf(z) > Rules.GOAL_HALF_WIDTH + 0.3 or y > Rules.GOAL_HEIGHT:
		return  # tir à côté ou au-dessus : le gardien ne bouge pas
	var time: float = prediction["time"]
	var offset := z - keeper.position.z
	var reach := Rules.keeper_reach(keeper, time)
	keeper.start_dive(clampf(z, keeper.position.z - reach, keeper.position.z + reach), minf(time, 0.6))
	if absf(offset) > reach:
		event_logged.emit("Tir hors de portée du gardien", "info")
		return
	var chance := Rules.keeper_chance(keeper, velocity.length(), absf(offset) / reach, y)
	var result := Dice.resolve(chance)
	if Dice.is_success(result):
		keeper.pending_save = {"tier": result["tier"], "sign": signf(ball.global_position.x - keeper.position.x), "result": result}
	elif result["tier"] == "crit_fail":
		_log_dice("Le ballon passe à travers le gardien !", result)
	else:
		_log_dice("Le gardien est battu", result)


func _apply_pending_save(keeper: Player) -> void:
	var bp := ball.global_position
	var sign_before: float = keeper.pending_save["sign"]
	var arrived := absf(bp.x - keeper.position.x) < 1.0 or signf(bp.x - keeper.position.x) != sign_before
	if not arrived:
		return
	var result: Dictionary = keeper.pending_save["result"]
	keeper.pending_save = {}
	var close := absf(bp.z - keeper.position.z) <= 1.8 and bp.y <= 2.6
	if not close:
		return
	var speed := ball.linear_velocity.length()
	var catch_result := Dice.resolve(Rules.keeper_catch_chance(keeper, speed))
	if result["tier"] == "crit_success" or Dice.is_success(catch_result):
		ball.linear_velocity = Vector3.ZERO
		set_holder(keeper)
		_log_dice("Arrêt du gardien (capté)", result)
	else:
		var out_dir := Rules.attack_dir(keeper.team)
		var rebound := Vector3(out_dir * Dice.rng.randf_range(2.5, 6.0), Dice.rng.randf_range(1.5, 3.5), Dice.rng.randf_range(-5.0, 5.0))
		ball.deflect(keeper, rebound)
		keeper.contact_lock = 0.6
		_log_dice("Arrêt du gardien (repoussé)", result)


# --- Sorties, buts, mi-temps -----------------------------------------------------------------

func _check_out_of_play() -> void:
	var bp := ball.global_position
	if absf(bp.x) > Rules.HALF_LENGTH + Ball.RADIUS:
		var scoring_team := 0 if bp.x > 0.0 else 1
		if absf(bp.z) < Rules.GOAL_HALF_WIDTH - 0.06 and bp.y < Rules.GOAL_HEIGHT:
			_goal(scoring_team)
		elif ball.last_touch_team == 1 - scoring_team:
			var corner := Vector3(signf(bp.x) * (Rules.HALF_LENGTH - 0.4), 0.0, signf(bp.z) * (Rules.HALF_WIDTH - 0.4))
			_restart(scoring_team, corner, "CORNER", TEAM_NAMES[scoring_team])
		else:
			var spot := Vector3(signf(bp.x) * (Rules.HALF_LENGTH - 5.0), 0.0, 0.0)
			_restart(1 - scoring_team, spot, "SORTIE DE BUT", TEAM_NAMES[1 - scoring_team])
	elif absf(bp.z) > Rules.HALF_WIDTH + Ball.RADIUS:
		var team := 1 - maxi(ball.last_touch_team, 0)
		var spot := Vector3(clampf(bp.x, -Rules.HALF_LENGTH + 1.0, Rules.HALF_LENGTH - 1.0), 0.0, signf(bp.z) * (Rules.HALF_WIDTH - 0.3))
		_restart(team, spot, "TOUCHE", TEAM_NAMES[team])


func _goal(team: int) -> void:
	score[team] += 1
	phase = Phase.GOAL
	_dead_timer = 3.0
	_next_kickoff_team = 1 - team
	freeze_requested.emit(true)
	var scorer := ball.last_toucher
	var by := " — N°%d" % scorer.number if scorer != null and scorer.team == team else ""
	event_logged.emit("BUT pour les %s%s" % [TEAM_NAMES[team].to_lower(), by], "goal")
	banner_requested.emit("BUT !", "%d - %d" % [score[0], score[1]])


func _end_half() -> void:
	phase = Phase.HALF_TIME
	_dead_timer = 3.0
	_next_kickoff_team = 1
	freeze_requested.emit(true)
	banner_requested.emit("MI-TEMPS", "%d - %d" % [score[0], score[1]])


func _end_match() -> void:
	phase = Phase.FULL_TIME
	freeze_requested.emit(true)
	banner_requested.emit("FIN DU MATCH", "%d - %d" % [score[0], score[1]])
	full_time.emit()


func begin_kickoff(team: int) -> void:
	_clear_all_orders()
	for p in players:
		p.position = slot_position(p.team, players.find(p) % FORMATION.size())
		p.speed = 0.0
		p.ai_goal = null
		p.stun_time = 0.0
		p.dive.clear()
		p.pending_save = {}
		p.heading = Vector3.RIGHT if p.team == 0 else Vector3.LEFT
		p.rotation.y = atan2(p.heading.x, p.heading.z)
	var kicker := player_at(team, 3)
	kicker.position = Vector3(-Rules.attack_dir(team) * 0.7, 0.0, 0.0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.global_position = Vector3(0.0, Ball.RADIUS, 0.0)
	ball.curve = 0.0
	ball.holder = null
	possession_team = -1
	set_holder(kicker)
	possession_team = team
	_auto_pause_armed = false
	freeze_requested.emit(false)
	banner_requested.emit("COUP D'ENVOI", "Les %s engagent" % TEAM_NAMES[team].to_lower())
	dead_ball_pause_requested.emit()


func _restart(team: int, spot: Vector3, title: String, team_name: String) -> void:
	_clear_all_orders()
	var taker: Player = null
	var best := 1e9
	for p in players:
		if p.team != team or p.stun_time > 0.0:
			continue
		if p.is_keeper and title != "SORTIE DE BUT":
			continue
		if title == "SORTIE DE BUT" and not p.is_keeper:
			continue
		var d := Vector2(p.position.x - spot.x, p.position.z - spot.z).length()
		if d < best:
			best = d
			taker = p
	if taker == null:
		taker = player_at(team, 0)
	var attack := Rules.attack_dir(team)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.curve = 0.0
	ball.holder = null
	ball.global_position = Vector3(spot.x, Ball.RADIUS, spot.z)
	taker.position = Vector3(spot.x - attack * 0.6, 0.0, spot.z)
	taker.speed = 0.0
	taker.heading = Vector3(attack, 0.0, 0.0)
	possession_team = team
	set_holder(taker)
	_auto_pause_armed = false
	banner_requested.emit(title, "Remise en jeu : %s" % team_name.to_lower())
	dead_ball_pause_requested.emit()


# --- IA ------------------------------------------------------------------------------------

func _run_ai() -> void:
	var nearest_to_ball := [null, null]
	var nearest_dist := [1e9, 1e9]
	var bp := ball.global_position
	for p in players:
		if p.is_keeper:
			continue
		var d := Vector2(p.position.x - bp.x, p.position.z - bp.z).length()
		if d < nearest_dist[p.team]:
			nearest_dist[p.team] = d
			nearest_to_ball[p.team] = p

	for p in players:
		if p.has_orders() or p.stun_time > 0.0 or not p.dive.is_empty():
			continue
		if p.is_keeper:
			_ai_keeper(p)
		elif ball.holder == p:
			_ai_carrier(p)
		elif ball.holder == null:
			if nearest_to_ball[p.team] == p:
				var lead := bp + Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z) * 0.3
				p.ai_goal = {"pos": lead, "allure": Player.Allure.SPRINT if nearest_dist[p.team] > 3.0 else Player.Allure.TROT, "final": false}
			else:
				p.ai_goal = _slot_goal(p, false)
		elif ball.holder.team == p.team:
			p.ai_goal = _slot_goal(p, true)
		else:
			if nearest_to_ball[p.team] == p:
				_ai_press(p)
			else:
				p.ai_goal = _slot_goal(p, false)


func _slot_goal(p: Player, attacking: bool) -> Dictionary:
	var index := players.find(p) % FORMATION.size()
	var slot := slot_position(p.team, index)
	var dir := Rules.attack_dir(p.team)
	var progress := ball.global_position.x * dir
	var shift := clampf(progress * 0.5, -10.0, 12.0)
	shift += (5.0 if p.role == "ATT" else 2.0) if attacking else -2.0
	if p.role == "DEF":
		shift *= 0.6
	var target := Vector3(clampf(slot.x + dir * shift, -Rules.HALF_LENGTH + 2.0, Rules.HALF_LENGTH - 2.0), 0.0, lerpf(slot.z, ball.global_position.z, 0.25))
	var distance := Rules.horizontal_distance(p.position, target)
	return {"pos": target, "allure": Player.Allure.TROT if distance > 4.0 else Player.Allure.MARCHE, "final": true}


func _ai_press(p: Player) -> void:
	var carrier := ball.holder
	var distance := Rules.horizontal_distance(p.position, carrier.position)
	p.ai_goal = {"pos": carrier.position, "allure": Player.Allure.SPRINT if distance > 3.0 else Player.Allure.TROT, "final": false}
	if distance <= Player.TACKLE_RANGE and p.tackle_cooldown <= 0.0 and p.decision_timer <= 0.0:
		p.decision_timer = 1.4
		if Dice.rng.randf() < 0.45:
			do_tackle(p, carrier)


func _ai_keeper(p: Player) -> void:
	if ball.holder == p:
		p.ai_goal = null
		if p.decision_timer <= 0.0:
			var target := _best_pass_target(p, 0.0)
			if target == null:
				target = teammates_of(p).filter(func(t): return not t.is_keeper)[0]
			var far := Rules.horizontal_distance(p.position, target.position) > 18.0
			do_pass(p, {"type": "pass", "target": target, "aerial": far, "power": 1.0, "curve": 0.0})
			p.decision_timer = 1.5
		return
	var dir := Rules.attack_dir(p.team)
	var own_goal_x := -dir * Rules.HALF_LENGTH
	var bp := ball.global_position
	var ball_near_goal := absf(bp.x - own_goal_x) < 9.0 and ball.holder == null
	if ball_near_goal and Rules.horizontal_distance(p.position, bp) < 7.0:
		p.ai_goal = {"pos": bp, "allure": Player.Allure.SPRINT, "final": false}
	else:
		var line_x := own_goal_x + dir * 2.0
		p.ai_goal = {"pos": Vector3(line_x, 0.0, clampf(bp.z * 0.45, -2.4, 2.4)), "allure": Player.Allure.TROT, "final": true}


func _ai_carrier(p: Player) -> void:
	if p.team == human_team and p.hold_idle < HUMAN_CARRIER_PATIENCE:
		# Équipe pilotée : le porteur garde le ballon et attend les ordres du joueur.
		p.hold_idle += AI_INTERVAL
		p.ai_goal = null
		return
	if p.decision_timer > 0.0:
		p.ai_goal = {"pos": p.position + p.heading * 3.0, "allure": Player.Allure.TROT, "final": false}
		return
	var dir := Rules.attack_dir(p.team)
	var goal := Vector3(Rules.goal_x(p.team), 0.0, 0.0)
	var distance_to_goal := Rules.horizontal_distance(p.position, goal)
	var nearest := 99.0
	for o in opponents_of(p):
		nearest = minf(nearest, Rules.horizontal_distance(p.position, o.position))

	if distance_to_goal <= 17.0 and absf(p.position.z) < 11.0 and nearest > 2.5 and not Rules.lane_blocked(p.position, goal, p.team, players, 1.3):
		var keeper := player_at(1 - p.team, 0)
		var z := Dice.rng.randf_range(-2.2, 2.2)
		if Dice.rng.randf() < 0.35:
			z = (1.0 if keeper.position.z < 0.0 else -1.0) * Dice.rng.randf_range(1.5, 2.5)
		var roll := Dice.rng.randf()
		var level := 1 if roll < 0.55 else (0 if roll < 0.9 else 2)
		do_shoot(p, {"type": "shoot", "z": z, "height": level, "power": 0.7, "curve": 0.0})
		p.decision_timer = 0.8
		return
	if nearest < 2.5:
		var target := _best_pass_target(p, 0.0)
		if target != null:
			do_pass(p, {"type": "pass", "target": target, "aerial": false, "power": 1.0, "curve": 0.0})
			p.decision_timer = 0.8
			return
	var run_to := Vector3(goal.x - dir * 12.0, 0.0, clampf(p.position.z * 0.7, -10.0, 10.0))
	p.ai_goal = {"pos": run_to, "allure": Player.Allure.SPRINT if nearest > 9.0 else Player.Allure.TROT, "final": false}


## Meilleur coéquipier à qui passer : devant, démarqué, à bonne distance.
func _best_pass_target(p: Player, min_free: float) -> Player:
	var dir := Rules.attack_dir(p.team)
	var best: Player = null
	var best_score := -1e9
	for t in teammates_of(p):
		if t.is_keeper or t.stun_time > 0.0:
			continue
		var distance := Rules.horizontal_distance(p.position, t.position)
		if distance < 5.0 or distance > 26.0:
			continue
		var free := 99.0
		for o in opponents_of(p):
			free = minf(free, Rules.horizontal_distance(t.position, o.position))
		if free < maxf(2.5, min_free):
			continue
		if Rules.lane_blocked(p.position, t.position, p.team, players, 1.6):
			continue
		var score: float = (t.position.x - p.position.x) * dir * 0.6 + minf(free, 10.0)
		if score > best_score:
			best_score = score
			best = t
	return best
