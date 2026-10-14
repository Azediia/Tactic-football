extends SceneTree
## Génère des captures d'écran de l'interface (nécessite un affichage, ex. xvfb-run) :
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/screenshot.gd -- /chemin/dossier

func _initialize() -> void:
	var out_dir := "/tmp"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	Dice.seed_with(5)
	root.size = Vector2i(1280, 720)
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	_save(out_dir + "/1_coup_d_envoi.png")

	# Quelques ordres pour illustrer les tracés.
	var d := main.director
	main.select_player(d.player_at(0, 3))
	var p3 := d.player_at(0, 3)
	var p4 := d.player_at(0, 4)
	p3.add_order(Vector3(8.0, 0.0, -4.0), Player.Allure.TROT)
	p3.add_action_order({"type": "pass", "target": p4, "aerial": false, "power": 1.0, "curve": 0.5})
	p4.add_order(Vector3(16.0, 0.0, 6.0), Player.Allure.SPRINT)
	p4.add_action_order({"type": "shoot", "z": 1.5, "height": 1, "power": 0.8, "curve": 0.0})
	main.set_mode(Main.Mode.PASS)
	for i in 4:
		await process_frame
	_save(out_dir + "/2_ordres_passe.png")

	main.set_mode(Main.Mode.SHOOT)
	for i in 4:
		await process_frame
	_save(out_dir + "/3_menu_tir.png")

	# Match en direct.
	main.pause_kind = "tactical"
	main.set_paused(false)
	for i in 240:
		await process_frame
	_save(out_dir + "/4_en_direct.png")
	quit(0)


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("capture : ", path, " ", image.get_size())
