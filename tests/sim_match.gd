extends SceneTree
## Simulation d'un match complet IA contre IA, pour vérifier l'équilibre du jeu.
##   godot --headless --fixed-fps 120 --path . -s tests/sim_match.gd
## Argument optionnel : graine des dés (ex. -- 7).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	Dice.seed_with(int(args[0]) if args.size() > 0 else 1)
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var director := main.director
	director.human_team = -1  # les deux équipes sont jouées par l'IA
	var counts := {}
	director.event_logged.connect(func(text: String, kind: String):
		var key := "autre"
		if text.contains("Passe"): key = "passes"
		elif text.contains("tire"): key = "tirs"
		elif text.contains("tacle"): key = "tacles"
		elif text.contains("Arrêt"): key = "arrêts gardien"
		elif text.contains("BUT"): key = "buts"
		elif text.contains("change de camp"): key = "changements de possession"
		elif text.contains("trop loin"): key = "balles trop longues"
		elif text.contains("contrôle"): key = "contrôles"
		counts[key] = counts.get(key, 0) + 1)
	var restarts := [0]
	var auto_pauses := [0]
	director.ball_stopped.connect(func(): auto_pauses[0] += 1)
	director.dead_ball_pause_requested.connect(func(): restarts[0] += 1)
	var frames := 0
	while director.phase != MatchDirector.Phase.FULL_TIME and frames < 90000:
		await physics_frame
		frames += 1
		if main.paused:
			main.set_paused(false)
	print("Durée simulée : %.0f s — score %d-%d — remises en jeu : %d — pauses ballon arrêté : %d" % [director.clock, director.score[0], director.score[1], restarts[0], auto_pauses[0]])
	var keys := counts.keys()
	keys.sort()
	for key in keys:
		print("  %s : %d" % [key, counts[key]])
	var minutes_stamina := 0.0
	for p in director.players:
		minutes_stamina += p.stamina
	print("Énergie moyenne en fin de match : %.0f %%" % (minutes_stamina / director.players.size()))
	quit(0)
