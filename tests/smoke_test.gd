extends SceneTree
## Tests automatiques. Lancer avec :
##   godot --headless --fixed-fps 120 --path . -s tests/smoke_test.gd
## Les messages "mesh_get_surface_count" du mode sans écran sont normaux.

var _failures := 0
var main: Main
var director: MatchDirector


func _initialize() -> void:
	Dice.seed_with(12345)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	director = main.director
	director.ai_enabled = false

	_test_dice()
	_test_rules()
	await _test_start_state()
	await _test_ball_physics()
	await _test_pause()
	await _test_player_orders()
	await _test_dribble()
	await _test_pass()
	await _test_goal()
	await _test_keeper_save()
	await _test_tackle()
	await _test_possession_clears_orders()
	await _test_out_of_play()
	await _test_ui()
	await _test_ai_match()

	print("TESTS : ", "OK" if _failures == 0 else "ECHEC (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _resume() -> void:
	main.set_paused(false)
	main.pause_cooldown_left = 0.0


## Remet une situation propre : joueurs immobiles, ballon libre au centre, ordres vides.
func _reset_scene() -> void:
	Dice.clear_forced()
	director.phase = MatchDirector.Phase.LIVE
	main.frozen = false
	for p in director.players:
		p.clear_orders()
		p.ai_goal = null
		p.speed = 0.0
		p.stun_time = 0.0
		p.contact_lock = 0.0
		p.tackle_cooldown = 0.0
		p.dive.clear()
		p.pending_save = {}
		p.last_eval_shot = -1
		p.stamina = 100.0
	director.ball.holder = null
	director.ball.linear_velocity = Vector3.ZERO
	director.ball.angular_velocity = Vector3.ZERO
	director.ball.curve = 0.0
	director.ball.global_position = Vector3(0.0, Ball.RADIUS, 0.0)
	director.possession_team = -1
	_resume()


func _give_ball(p: Player) -> void:
	p.speed = 0.0
	director.ball.global_position = p.position + p.heading * 0.6 + Vector3(0.0, Ball.RADIUS, 0.0)
	director.ball.linear_velocity = Vector3.ZERO
	director.set_holder(p)


func _test_dice() -> void:
	print("Dés")
	Dice.clear_forced()
	var counts := {"crit_success": 0, "success": 0, "fail": 0, "crit_fail": 0}
	var n := 20000
	for i in n:
		counts[Dice.resolve(60.0)["tier"]] += 1
	_check(absf(float(counts["crit_success"]) / n - 0.06) < 0.01, "chance 60 : ~6 %% de réussites critiques (%.1f %%)" % (100.0 * counts["crit_success"] / n))
	_check(absf(float(counts["success"]) / n - 0.54) < 0.015, "chance 60 : ~54 %% de réussites simples (%.1f %%)" % (100.0 * counts["success"] / n))
	_check(counts["crit_fail"] == 0, "chance 60 : aucun échec critique possible")
	counts = {"crit_success": 0, "success": 0, "fail": 0, "crit_fail": 0}
	for i in n:
		counts[Dice.resolve(20.0)["tier"]] += 1
	_check(absf(float(counts["crit_fail"]) / n - 0.30) < 0.015, "chance 20 : ~30 %% d'échecs critiques (%.1f %%)" % (100.0 * counts["crit_fail"] / n))
	Dice.force(["crit_fail", "success"])
	_check(Dice.resolve(80.0)["tier"] == "crit_fail" and Dice.resolve(80.0)["tier"] == "success", "les jets peuvent être imposés (tests)")
	Dice.clear_forced()


func _test_rules() -> void:
	print("Règles")
	var from := Vector3(0.0, Ball.RADIUS, 0.0)
	var target := Vector3(20.0, 1.1, 1.5)
	var v := Rules.shot_velocity(from, target, 25.0)
	var t := (target.x - from.x) / v.x
	var y := from.y + v.y * t - 0.5 * Rules.GRAVITY * t * t
	_check(absf(y - target.y) < 0.02, "le tir passe à la hauteur visée (%.2f m pour %.2f m)" % [y, target.y])
	_check(absf(v.z * t - 1.5) < 0.02, "le tir arrive au bon endroit latéralement")
	var lob := Rules.lob_velocity(from, Vector3(18.0, 0.0, 0.0), 1.0)
	var flight := 2.0 * lob.y / Rules.GRAVITY
	_check(absf(lob.x * flight - 18.0) < 0.1, "la cloche retombe sur la cible (%.1f m)" % (lob.x * flight))
	var perfect := Rules.apply_error(Vector3(10, 0, 0), {"tier": "crit_success", "margin": 0.0})
	_check(perfect.is_equal_approx(Vector3(10, 0, 0)), "une réussite critique n'ajoute aucune erreur")
	var bad := Rules.apply_error(Vector3(10, 0, 0), {"tier": "crit_fail", "margin": 70.0})
	_check(absf(bad.signed_angle_to(Vector3(10, 0, 0), Vector3.UP)) > deg_to_rad(30.0) or bad.length() < 8.0 or bad.length() > 12.0, "un échec critique dévie nettement la frappe")


func _test_start_state() -> void:
	print("Début de match")
	_check(director.players.size() == 10, "10 joueurs en jeu (5 contre 5)")
	_check(main.paused and main.pause_kind == "dead_ball", "le match commence par une pause offerte")
	_check(director.ball.holder != null and director.ball.holder.team == 0, "les bleus engagent avec le ballon")
	_check(main.selected != null and not main.selected.is_keeper, "un joueur de champ est sélectionné")
	_check(MatchDirector.HALF_DURATION * 2.0 == 600.0, "le match dure 10 minutes (2 x 5)")


func _test_ball_physics() -> void:
	print("Ballon")
	_reset_scene()
	var ball := director.ball
	ball.global_position = Vector3(-10.0, Ball.RADIUS, 15.0)  # loin de tous les joueurs
	ball.linear_velocity = Vector3(14.0, 6.0, 0.0)
	var max_height := 0.0
	for i in 240:
		await physics_frame
		max_height = maxf(max_height, ball.global_position.y)
	_check(ball.global_position.x > 5.0, "le ballon avance après une frappe (x = %.1f)" % ball.global_position.x)
	_check(max_height > 0.5, "le ballon monte (%.2f m)" % max_height)
	_check(ball.global_position.y > 0.0, "le ballon reste au-dessus du terrain")
	# Effet : un ballon avec de l'effet dévie latéralement.
	_reset_scene()
	ball.holder = null
	ball.global_position = Vector3(-10.0, Ball.RADIUS, 15.0)
	ball.kick(director.player_at(1, 4), Vector3(16.0, 0.0, 0.0), 1.0)
	await _frames(100)
	_check(absf(ball.global_position.z) > 1.0, "l'effet fait dévier le ballon (%.1f m)" % ball.global_position.z)


func _test_pause() -> void:
	print("Pause")
	_reset_scene()
	main.set_paused(false)
	director.ball.linear_velocity = Vector3(10.0, 4.0, 0.0)
	await _frames(20)
	main.pause_cooldown_left = 0.0
	main.toggle_pause()
	_check(main.paused and main.pause_kind == "tactical", "la pause tactique s'active")
	var frozen_at := director.ball.global_position
	await _frames(60)
	_check(director.ball.global_position.is_equal_approx(frozen_at), "le ballon est figé pendant la pause")
	var clock_before := director.clock
	await _frames(30)
	_check(is_equal_approx(director.clock, clock_before), "l'horloge du match s'arrête en pause")
	main.toggle_pause()
	_check(not main.paused and main.pause_cooldown_left > 0.0, "le cooldown démarre à la reprise")
	main.toggle_pause()
	_check(not main.paused, "pas de nouvelle pause pendant le cooldown")
	main.pause_cooldown_left = 0.0
	main.set_paused(true)
	main.pause_kind = "dead_ball"
	main.toggle_pause()
	_check(not main.paused and main.pause_cooldown_left == 0.0, "une pause offerte ne déclenche pas de cooldown")


func _test_player_orders() -> void:
	print("Ordres et inertie")
	_reset_scene()
	var player := director.player_at(0, 3)
	player.position = Vector3(-10.0, 0.0, 10.0)
	player.heading = Vector3.RIGHT
	var start := player.position
	player.add_order(start + Vector3(20.0, 0.0, 0.0), Player.Allure.SPRINT)
	var top := 0.0
	for i in 600:
		await physics_frame
		top = maxf(top, player.speed)
	var distance := player.position.distance_to(start + Vector3(20.0, 0.0, 0.0))
	_check(top > 6.0, "le sprint atteint une vitesse élevée (%.1f m/s)" % top)
	_check(top <= player.top_speed() + 0.01, "la vitesse ne dépasse pas la vitesse de pointe")
	_check(distance < 1.0 and player.speed < 0.05, "le joueur s'arrête sur son dernier point (%.2f m)" % distance)
	_check(player.orders.is_empty(), "les points atteints sont retirés")

	player.speed = player.top_speed()
	player.heading = Vector3.RIGHT
	player.add_order(player.position + Vector3(-15.0, 0.0, 0.0), Player.Allure.SPRINT)
	var worst_turn := 0.0
	var min_speed := player.speed
	var previous := player.heading
	for i in 120:
		await physics_frame
		worst_turn = maxf(worst_turn, previous.angle_to(player.heading))
		previous = player.heading
		min_speed = minf(min_speed, player.speed)
	var limit: float = Player.TURN_RATE_STILL / float(Engine.physics_ticks_per_second) + 0.0001
	_check(worst_turn <= limit, "la rotation par pas est bornée par l'inertie")
	_check(min_speed < 3.0, "demi-tour à pleine vitesse : le joueur ralentit (%.1f m/s)" % min_speed)
	player.clear_orders()

	# Fatigue.
	_reset_scene()
	var runner := director.player_at(0, 4)
	runner.position = Vector3(-20.0, 0.0, 15.0)
	runner.add_order(Vector3(20.0, 0.0, 15.0), Player.Allure.SPRINT)
	await _frames(300)
	_check(runner.stamina < 99.9, "le sprint fatigue le joueur (énergie %.1f)" % runner.stamina)
	runner.stamina = 0.0
	_check(runner.effective_stat("passe") < float(runner.stats["passe"]) - 20.0, "la fatigue réduit les stats (-25 au plus)")
	runner.clear_orders()


func _test_dribble() -> void:
	print("Conduite de balle")
	_reset_scene()
	var carrier := director.player_at(0, 3)
	carrier.position = Vector3(-15.0, 0.0, 12.0)
	carrier.heading = Vector3.RIGHT
	_give_ball(carrier)
	carrier.add_order(Vector3(10.0, 0.0, 12.0), Player.Allure.TROT)
	var kept := 0
	var frames := 360
	for i in frames:
		await physics_frame
		if director.ball.holder == carrier:
			kept += 1
	var ball_gap := Rules.horizontal_distance(carrier.position, director.ball.global_position)
	_check(float(kept) / frames > 0.9, "un bon technicien garde le ballon au trot (%.0f %% du temps)" % (100.0 * kept / frames))
	_check(carrier.position.x > -5.0, "le porteur avance avec le ballon (x = %.1f)" % carrier.position.x)
	_check(ball_gap < 3.0, "le ballon reste près du porteur (%.1f m)" % ball_gap)

	# Un joueur maladroit en sprint pousse le ballon trop loin.
	_reset_scene()
	var clumsy := director.player_at(0, 4)
	clumsy.stats["technique"] = 25
	clumsy.position = Vector3(-25.0, 0.0, -12.0)
	clumsy.heading = Vector3.RIGHT
	_give_ball(clumsy)
	clumsy.add_order(Vector3(20.0, 0.0, -12.0), Player.Allure.SPRINT)
	var lost := false
	for i in 400:
		await physics_frame
		if director.ball.holder != clumsy:
			lost = true
			break
	_check(lost, "un joueur maladroit en sprint perd le contrôle du ballon")
	clumsy.clear_orders()


func _test_pass() -> void:
	print("Passe")
	_reset_scene()
	var passer := director.player_at(0, 3)
	var receiver := director.player_at(0, 4)
	passer.position = Vector3(-6.0, 0.0, 0.0)
	receiver.position = Vector3(8.0, 0.0, 3.0)
	_give_ball(passer)
	passer.add_action_order({"type": "pass", "target": receiver, "aerial": false, "power": 1.0, "curve": 0.0})
	Dice.force(["success", "success"])
	await _frames(300)
	_check(director.ball.holder == receiver, "la passe arrive au receveur (porteur : %s)" % (director.ball.holder.display_name if director.ball.holder != null else "personne"))

	# Passe ratée : le ballon part de travers.
	_reset_scene()
	passer.position = Vector3(-6.0, 0.0, 0.0)
	receiver.position = Vector3(8.0, 0.0, 3.0)
	_give_ball(passer)
	passer.add_action_order({"type": "pass", "target": receiver, "aerial": false, "power": 1.0, "curve": 0.0})
	Dice.force(["crit_fail"])
	await _frames(240)
	_check(director.ball.holder != receiver, "une passe ratée critique n'arrive pas au receveur")

	# Ordre de passe en attente : le joueur ne l'exécute qu'une fois le ballon reçu.
	_reset_scene()
	passer.position = Vector3(0.0, 0.0, -10.0)
	receiver.position = Vector3(10.0, 0.0, -10.0)
	director.player_at(0, 1).position = Vector3(-10.0, 0.0, -10.0)
	var giver := director.player_at(0, 1)
	_give_ball(giver)
	giver.add_action_order({"type": "pass", "target": passer, "aerial": false, "power": 1.0, "curve": 0.0})
	passer.add_action_order({"type": "pass", "target": receiver, "aerial": false, "power": 1.0, "curve": 0.0})
	Dice.force(["success", "success", "success", "success"])
	await _frames(500)
	_check(passer.orders.is_empty(), "l'ordre de passe en attente est exécuté après réception")
	_check(director.ball.holder == receiver, "enchaînement de deux passes jusqu'au dernier receveur")
	Dice.clear_forced()


func _test_goal() -> void:
	print("But")
	_reset_scene()
	var shooter := director.player_at(0, 3)
	shooter.position = Vector3(20.0, 0.0, 0.0)
	_give_ball(shooter)
	var before: int = director.score[0]
	shooter.add_action_order({"type": "shoot", "z": 2.0, "height": 1, "power": 0.9, "curve": 0.0})
	Dice.force(["crit_success", "fail"])  # tir parfait, le gardien est battu
	await _frames(240)
	_check(director.score[0] == before + 1, "un tir parfait cadré marque (score %d)" % director.score[0])
	_check(director.phase == MatchDirector.Phase.GOAL, "le jeu se fige après le but")
	await _frames(500)
	_check(director.phase == MatchDirector.Phase.LIVE and main.paused, "coup d'envoi puis pause offerte")
	_check(director.ball.holder != null and director.ball.holder.team == 1, "l'équipe qui a encaissé engage")
	_check(director.ball.global_position.length() < 1.5, "le ballon est remis au centre")

	# Tir complètement raté : pas de but.
	_reset_scene()
	shooter.position = Vector3(20.0, 0.0, 0.0)
	_give_ball(shooter)
	var score_now: int = director.score[0]
	shooter.add_action_order({"type": "shoot", "z": 2.0, "height": 1, "power": 0.9, "curve": 0.0})
	Dice.force(["crit_fail"])
	await _frames(300)
	_check(director.score[0] == score_now, "un échec critique ne marque pas")
	Dice.clear_forced()


func _test_keeper_save() -> void:
	print("Gardien")
	_reset_scene()
	var keeper := director.player_at(1, 0)
	keeper.position = Vector3(27.0, 0.0, 0.0)
	var shooter := director.player_at(0, 3)
	shooter.position = Vector3(18.0, 0.0, 0.0)
	_give_ball(shooter)
	shooter.add_action_order({"type": "shoot", "z": 1.0, "height": 1, "power": 0.9, "curve": 0.0})
	Dice.force(["crit_success", "success", "success"])  # tir parfait, arrêt réussi, ballon capté
	await _frames(200)
	_check(director.ball.holder == keeper, "le gardien capte un tir cadré quand ses jets réussissent")

	_reset_scene()
	keeper.position = Vector3(27.0, 0.0, 0.0)
	shooter.position = Vector3(18.0, 0.0, 0.0)
	_give_ball(shooter)
	shooter.add_action_order({"type": "shoot", "z": 1.0, "height": 1, "power": 0.9, "curve": 0.0})
	Dice.force(["crit_success", "success", "fail"])  # arrêt réussi mais ballon non capté : repoussé
	await _frames(40)
	_check(director.ball.holder != keeper, "un arrêt non capté repousse le ballon")
	await _frames(100)

	# Un tir hors de portée du gardien n'implique aucun jet.
	_reset_scene()
	keeper.position = Vector3(27.0, 0.0, -2.5)
	shooter.position = Vector3(18.0, 0.0, 0.0)
	_give_ball(shooter)
	shooter.add_action_order({"type": "shoot", "z": 2.8, "height": 0, "power": 1.0, "curve": 0.0})
	Dice.force(["crit_success"])
	var goals: int = director.score[0]
	await _frames(240)
	_check(director.score[0] == goals + 1, "le tir dans l'angle opposé est hors de portée : but")
	Dice.clear_forced()


func _test_tackle() -> void:
	print("Tacle")
	_reset_scene()
	var tackler := director.player_at(0, 1)
	var carrier := director.player_at(1, 3)
	tackler.position = Vector3(-10.0, 0.0, 5.0)
	carrier.position = Vector3(-9.0, 0.0, 5.0)
	_give_ball(carrier)
	Dice.force(["success"])
	director.do_tackle(tackler, carrier)
	_check(director.ball.holder == tackler, "un tacle réussi prend le ballon")

	_reset_scene()
	tackler.position = Vector3(-10.0, 0.0, 5.0)
	carrier.position = Vector3(-9.0, 0.0, 5.0)
	_give_ball(carrier)
	Dice.force(["crit_fail"])
	director.do_tackle(tackler, carrier)
	_check(director.ball.holder == carrier and tackler.stun_time > 1.0, "un tacle raté critique laisse le défenseur au sol")

	# Ordre de tacle : le défenseur poursuit le porteur.
	_reset_scene()
	tackler.position = Vector3(-18.0, 0.0, 5.0)
	carrier.position = Vector3(-12.0, 0.0, 5.0)
	_give_ball(carrier)
	tackler.add_action_order({"type": "tackle", "target": carrier})
	Dice.force(["success"])
	await _frames(240)
	_check(director.ball.holder == tackler, "l'ordre de tacle poursuit le porteur puis tacle")
	Dice.clear_forced()


func _test_possession_clears_orders() -> void:
	print("Changement de camp")
	_reset_scene()
	var mine := director.player_at(0, 3)
	var other := director.player_at(0, 4)
	var rival := director.player_at(1, 3)
	_give_ball(mine)
	other.add_order(Vector3(5.0, 0.0, 5.0), Player.Allure.TROT)
	mine.add_order(Vector3(10.0, 0.0, 0.0), Player.Allure.TROT)
	_check(other.has_orders() and mine.has_orders(), "des ordres sont en attente")
	director.set_holder(rival)
	_check(not other.has_orders() and not mine.has_orders(), "tous les ordres sont annulés quand le ballon change de camp")


func _test_out_of_play() -> void:
	print("Sorties de balle")
	_reset_scene()
	director.ball.last_touch_team = 0
	director.ball.global_position = Vector3(5.0, Ball.RADIUS, 20.6)
	await _frames(3)
	_check(director.ball.holder != null and director.ball.holder.team == 1, "touche pour l'équipe adverse du dernier toucheur")
	_check(main.paused and main.pause_kind == "dead_ball", "pause offerte sur remise en jeu")
	_check(absf(director.ball.global_position.z) < 20.5, "le ballon est replacé sur la ligne")

	_reset_scene()
	director.ball.last_touch_team = 1
	director.ball.global_position = Vector3(30.5, Ball.RADIUS, 8.0)
	await _frames(3)
	_check(director.ball.holder != null and director.ball.holder.team == 0, "corner pour les attaquants")

	_reset_scene()
	director.ball.last_touch_team = 0
	director.ball.global_position = Vector3(30.5, Ball.RADIUS, 8.0)
	await _frames(3)
	_check(director.ball.holder != null and director.ball.holder.team == 1 and director.ball.holder.is_keeper, "sortie de but : le gardien relance")


func _test_ui() -> void:
	print("Interface")
	_reset_scene()
	main.set_paused(true)
	main.pause_kind = "tactical"
	var player := director.player_at(0, 3)
	main.select_player(player)
	await _frames(2)
	_check(main.ui._menu.visible, "le menu contextuel apparaît en pause")
	main.set_mode(Main.Mode.PASS)
	main.hover_ground = director.player_at(0, 4).position
	var preview := main.compute_preview()
	_check(not preview.is_empty() and preview["chance"] > 1.0, "la passe affiche un pourcentage (%d %%)" % int(preview.get("chance", 0)))
	main.set_mode(Main.Mode.SHOOT)
	main.hover_ground = Vector3(30.0, 0.0, 1.0)
	preview = main.compute_preview()
	_check(not preview.is_empty() and preview.has("crit_fail"), "le tir affiche ses probabilités")
	main.opt_curve = 4
	main.adjust_curve(1)
	_check(main.opt_curve == 4, "l'effet est borné")
	_check(absf(main.effective_curve()) <= Rules.max_curve(player) + 0.001, "l'effet est limité par la technique")
	main.set_mode(Main.Mode.MOVE)
	main.opt_curve = 0
	main.ui.add_event("Test — jet 12 / 70 : réussie", "dice")
	main.ui.show_banner("TEST", "bannière")
	await _frames(2)
	_check(main.ui._banner_box.visible, "les bannières s'affichent")
	main.ui.show_end()
	_check(main.ui._end_box.visible, "l'écran de fin s'affiche")
	main.ui._end_box.visible = false
	main.ui._banner_box.visible = false


func _test_ai_match() -> void:
	print("Match complet (IA contre IA, 60 s)")
	_reset_scene()
	director.ai_enabled = true
	director.begin_kickoff(0)
	director.clock = 0.0
	var score_before: Array = director.score.duplicate()
	var goals_seen := [0]
	var restarts := [0]
	director.event_logged.connect(func(text: String, kind: String): goals_seen[0] += 1 if kind == "goal" else 0)
	director.dead_ball_pause_requested.connect(func(): restarts[0] += 1)
	var shots := [0]
	director.event_logged.connect(func(text: String, kind: String): shots[0] += 1 if text.contains("tire") else 0)
	var changes := [0]
	director.event_logged.connect(func(text: String, kind: String): changes[0] += 1 if text.contains("change de camp") else 0)
	var bad := false
	var max_out := 0.0
	for i in 7200:
		await physics_frame
		if main.paused:
			main.set_paused(false)
		for p in director.players:
			if not is_finite(p.position.x) or not is_finite(p.position.z):
				bad = true
			max_out = maxf(max_out, maxf(absf(p.position.x) - 30.0, absf(p.position.z) - 20.0))
		if not is_finite(director.ball.global_position.x):
			bad = true
	print("  info clock=%.0fs buts=%d-%d tirs=%d changements=%d remises=%d hors-limites=%.1fm" % [director.clock, director.score[0] - score_before[0], director.score[1] - score_before[1], shots[0], changes[0], restarts[0], max_out])
	_check(not bad, "aucune position invalide (NaN) pendant le match")
	_check(director.clock > 35.0, "l'horloge avance (%.0f s, hors célébrations)" % director.clock)
	_check(max_out < 6.0, "les joueurs restent près du terrain (%.1f m max hors limites)" % max_out)
	_check(shots[0] + restarts[0] + changes[0] > 2, "le match se déroule : tirs, remises et changements de possession")
	var far_ball := director.ball.global_position
	_check(absf(far_ball.x) < 40.0 and absf(far_ball.z) < 30.0, "le ballon reste en jeu")
