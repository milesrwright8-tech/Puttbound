extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var packed := load("res://scenes/puttbound.tscn") as PackedScene
	var world := packed.instantiate()
	root.add_child(world)
	for _i in range(8):
		await process_frame
	var title := root.get_viewport().get_texture().get_image()
	title.save_png("captures/puttbound_title.png")
	world.call("_start_hole", 0)
	for _i in range(12):
		await process_frame
	var game := root.get_viewport().get_texture().get_image()
	game.save_png("captures/puttbound_hole01.png")
	world.free()
	quit(0)
