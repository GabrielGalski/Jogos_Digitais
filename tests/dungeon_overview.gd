extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node2D = load("res://scenes/dungeon/dungeon_preview.tscn").instantiate() as Node2D
	root.add_child(scene)
	await create_timer(0.6).timeout
	scene.set_physics_process(false)
	scene.get_node("HUD").hide()
	var player: Player = scene.get_node("Nox") as Player
	player.intro_locked = true
	for path: String in ["Layout/Room2", "Layout/ExitDown", "Layout/ExitRight"]:
		(scene.get_node(path) as Node2D).modulate.a = 1.0
	var camera: Camera2D = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	scene.add_child(camera)
	camera.position = Vector2(384, -112)
	camera.zoom = Vector2.ONE * 0.36
	camera.make_current()
	camera.force_update_scroll()
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://renders/dungeon_overview.png")
	print("DUNGEON OVERVIEW SAVED")
	quit()
