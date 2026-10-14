extends SceneTree
## Tests de fumée : lancer avec
##   godot --headless --path . -s tests/smoke_test.gd
## Les messages "mesh_get_surface_count" du mode sans écran sont normaux.

var _failures := 0


func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame

	await _test_ball(main)
	await _test_pause(main)
	await _test_player_orders(main)

	print("SMOKE TEST : ", "OK" if _failures == 0 else "ECHEC (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures += 1


func _test_ball(main) -> void:
	print("Ballon")
	var start: Vector3 = main.ball.global_position
	main.kick()
	var max_height := 0.0
	for i in 360:
		await physics_frame
		max_height = maxf(max_height, main.ball.global_position.y)
	var end: Vector3 = main.ball.global_position
	_check(end.x - start.x > 5.0, "le ballon avance après une frappe")
	_check(max_height > 0.5, "le ballon monte (hauteur max %.2f m)" % max_height)
	_check(end.y > 0.0, "le ballon reste au-dessus du terrain")
	main.reset_ball()


func _test_pause(main) -> void:
	print("Pause")
	_check(main.players.size() == 10, "10 joueurs en jeu (5 contre 5)")
	main.kick()
	for i in 20:
		await physics_frame
	main.toggle_pause()
	_check(main.paused, "la pause s'active")
	var frozen: Vector3 = main.ball.global_position
	for i in 60:
		await physics_frame
	_check(main.ball.global_position.is_equal_approx(frozen), "le ballon est figé pendant la pause")
	main.toggle_pause()
	_check(not main.paused, "le jeu reprend")
	_check(main.pause_cooldown_left > 0.0, "le cooldown de pause démarre à la reprise")
	main.toggle_pause()
	_check(not main.paused, "impossible de re-pauser pendant le cooldown")
	main.pause_cooldown_left = 0.0
	main.reset_ball()


func _test_player_orders(main) -> void:
	print("Ordres et inertie")
	var player: Player = main.players[3]
	var start := player.position
	player.add_order(start + Vector3(20.0, 0.0, 0.0), Player.Allure.SPRINT)
	var top := 0.0
	var max_turn := 0.0
	var previous_heading := player.heading
	for i in 600:
		await physics_frame
		top = maxf(top, player.speed)
		max_turn = maxf(max_turn, previous_heading.angle_to(player.heading))
		previous_heading = player.heading
	var distance := player.position.distance_to(start + Vector3(20.0, 0.0, 0.0))
	_check(top > 6.0, "le sprint atteint une vitesse élevée (%.1f m/s)" % top)
	_check(top <= player.top_speed() + 0.01, "la vitesse ne dépasse pas la vitesse de pointe")
	_check(distance < 1.0, "le joueur s'arrête sur son dernier point (écart %.2f m)" % distance)
	_check(player.speed < 0.05, "le joueur est immobile à l'arrivée")
	_check(player.orders.is_empty(), "les points atteints sont retirés de la liste")

	# Demi-tour à pleine vitesse : l'inertie doit limiter la rotation par pas de temps.
	player.speed = player.top_speed()
	player.heading = Vector3.RIGHT
	player.add_order(player.position + Vector3(-15.0, 0.0, 0.0), Player.Allure.SPRINT)
	var worst_turn := 0.0
	var turn_previous := player.heading
	var min_speed := player.speed
	for i in 120:
		await physics_frame
		worst_turn = maxf(worst_turn, turn_previous.angle_to(player.heading))
		turn_previous = player.heading
		min_speed = minf(min_speed, player.speed)
	var limit: float = Player.TURN_RATE_STILL / float(Engine.physics_ticks_per_second) + 0.0001
	_check(worst_turn <= limit, "la rotation par pas reste bornée (%.4f rad ≤ %.4f)" % [worst_turn, limit])
	_check(min_speed < 3.0, "le joueur ralentit pour un demi-tour (vitesse mini %.1f m/s)" % min_speed)
	player.clear_orders()
