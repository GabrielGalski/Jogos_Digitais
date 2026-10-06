extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	change_scene_to_file("res://scenes/dungeon/ldtk_arena.tscn")
	await create_timer(0.6).timeout
	var player: Player = current_scene.get_node("Nox") as Player
	player.intro_locked = true
	(player.get_node("Camera2D") as Camera2D).enabled = false
	var camera: Camera2D = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var bounds: Rect2 = current_scene.get("_floor_bounds") as Rect2
	camera.position = bounds.get_center()
	camera.zoom = Vector2.ONE * minf(960.0 / maxf(bounds.size.x, 1.0), 540.0 / maxf(bounds.size.y, 1.0)) * 0.9
	current_scene.add_child(camera)
	camera.make_current()
	DirAccess.make_dir_recursive_absolute("res://tests")
	await _capture("overview")
	var column: Node2D = null
	for volume: Node in get_nodes_in_group("ldtk_map_volumes"):
		if str(volume.get_meta("kind", "")).begins_with("column"):
			column = volume as Node2D
			break
	if column == null:
		quit()
		return
	var origin: Vector2 = column.get_meta("authored_origin", Vector2.ZERO) as Vector2
	camera.position = origin + Vector2(16, 40)
	camera.zoom = Vector2.ONE * 4.0
	player.position = origin + Vector2(16, 35)
	player.reset_physics_interpolation()
	await _capture("behind")
	player.position = origin + Vector2(16, 70)
	player.reset_physics_interpolation()
	await _capture("front")
	quit()

func _capture(label: String) -> void:
	await physics_frame
	await physics_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/ldtk_" + label + ".png")
