extends SceneTree
## Test de fumée : la scène se charge, le ballon est frappé, retombe et rebondit sur le terrain.
## Lancer : godot --headless --path . -s tests/smoke_test.gd

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame

	var start: Vector3 = main.ball.global_position
	main.kick()
	var max_height := 0.0
	for i in 360:
		await physics_frame
		max_height = maxf(max_height, main.ball.global_position.y)

	var end: Vector3 = main.ball.global_position
	var moved := end.x - start.x
	var ok := moved > 5.0 and max_height > 0.5 and end.y > 0.0
	print("Ballon : départ=%s arrivée=%s hauteur max=%.2f" % [start, end, max_height])
	print("SMOKE TEST : ", "OK" if ok else "ECHEC")
	quit(0 if ok else 1)
