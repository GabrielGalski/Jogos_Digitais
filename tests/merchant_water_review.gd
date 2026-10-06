extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _run() -> void:
	root.size = Vector2i(512, 334)
	root.content_scale_size = root.size
	var packed: PackedScene = load("res://scenes/merchant/water.tscn") as PackedScene
	var water: Node2D = packed.instantiate() as Node2D
	root.add_child(water)
	water.set_process(false)
	var camera: Camera2D = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(camera)
	camera.position = Vector2(512, 167)
	camera.make_current()
	camera.force_update_scroll()
	var left_view: Image = await _capture()
	camera.position.x = 640.0
	camera.reset_physics_interpolation()
	camera.force_update_scroll()
	var right_view: Image = await _capture()
	var left_overlap: Image = left_view.get_region(Rect2i(128, 0, 384, 334))
	var right_overlap: Image = right_view.get_region(Rect2i(0, 0, 384, 334))
	assert(left_overlap.get_data() == right_overlap.get_data(),
		"The same world-space water pixels must remain unchanged when only the camera moves")
	var before: float = float(water.get("flow_offset"))
	water.call("_process", 0.5)
	assert(is_equal_approx(float(water.get("flow_offset")) - before, 11.0))
	var animated: Image = await _capture()
	assert(animated.get_data() != right_view.get_data(), "Water must move with elapsed time")
	animated.get_region(Rect2i(0, 280, 512, 54)).save_png("res://renders/merchant_water_preview.png")
	print("WATER PASS: fixed world pixels across camera motion; time advances current")
	quit()
