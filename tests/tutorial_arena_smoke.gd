extends SceneTree

func _initialize() -> void:
	call_deferred(&"run_checks")

func capture(path: String) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png(path) == OK)

func move_for(player: CharacterBody2D, start: Vector2, key: Key, frames: int) -> Vector2:
	player.position = start
	player.reset_physics_interpolation()
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	for i in range(frames): await physics_frame
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame
	return player.position

func run_checks() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node2D = main.get_node("TutorialArena")
	var player: CharacterBody2D = arena.get_node("Mox")
	var camera: Camera2D = player.get_node("Camera2D")
	assert(player.intro_locked)
	assert(player.position == Vector2(0, 344))
	await create_timer(0.9).timeout
	assert(player.position.y < 344 and player.position.y > 204)
	await capture("res://.godot/tutorial_arrival.png")
	await arena.entrance_finished
	arena.get_node("MinotaurChair").auto_start_encounter = false
	assert(player.position.is_equal_approx(Vector2(0, 204)))
	assert(not player.intro_locked)
	assert(not arena.get_node("EntranceStair").visible)
	assert(not camera.top_level and camera.is_current())
	assert(camera.limit_top == -772)
	assert(camera.limit_left == -238 and camera.limit_right == 498)
	assert(camera.limit_bottom == -148)
	print("INTRO_OK destination=", player.position, " stair hidden, input restored")
	await capture("res://.godot/tutorial_after_intro.png")
	var right := await move_for(player, Vector2(280, 200), KEY_D, 60)
	assert(right.x > 331 and right.x <= 332)
	var down := await move_for(player, Vector2(0, 204), KEY_S, 60)
	assert(down.y > 231 and down.y <= 232)
	var up := await move_for(player, Vector2(80, -280), KEY_W, 60)
	assert(up.y < -316 and up.y >= -318)
	print("BOUNDARIES_OK right=", right, " bottom=", down, " top=", up)
	var throne: StaticBody2D = arena.get_node("MinotaurChair")
	var behind := await move_for(player, Vector2(-40, throne.position.y - 45), KEY_D, 60)
	assert(behind.x > 35)
	var seat := await move_for(player, Vector2(0, throne.position.y + 45), KEY_W, 60)
	# The visible head must remain below the lowest step, not just the foot collider.
	assert(seat.y - 8.4 >= throne.position.y - 0.1, "seat=" + str(seat) + " throne=" + str(throne.position))
	assert(seat.y < throne.position.y + 15)
	for x in [-24, 24]:
		var side := await move_for(player, Vector2(x, throne.position.y + 45), KEY_W, 60)
		assert(side.y - 8.4 >= throne.position.y - 0.1)
	print("THRONE_OK back passage=", behind, " base blocks at=", seat)
	player.position = Vector2(0, throne.position.y - 45)
	player.reset_physics_interpolation()
	camera.reset_smoothing()
	await capture("res://.godot/tutorial_throne_back.png")
	# Validate a three-tile corridor with a temporary generic enemy-sized body.
	var walker := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5
	shape.shape = circle
	walker.add_child(shape)
	arena.add_child(walker)
	var points: Array[Vector2] = []
	for y in range(14, -14, -1):
		points.append(Vector2(0, y * 16 + 8))
	walker.position = points[0]
	await physics_frame
	for i in range(points.size()-1):
		var hit := walker.move_and_collide(points[i+1] - walker.position)
		assert(hit == null, "Path intersects a collider")
	walker.position = Vector2(0, throne.position.y + 45)
	var throne_hit := walker.move_and_collide(Vector2(0, -70))
	assert(throne_hit != null and throne_hit.get_collider() == throne)
	walker.queue_free()
	print("PATH_TRAVERSAL_OK")
	assert(arena.get_node("Floor").get_used_rect() == Rect2i(0, 0, 42, 35))
	for name in ["FarClouds", "NearClouds"]:
		var layer: Parallax2D = arena.get_node(name)
		assert(layer.get_child_count() == 1)
		assert(layer.get_child(0).texture.get_size() == Vector2(720, 640))
		var before: float = layer.scroll_offset.x
		await create_timer(0.2).timeout
		assert(layer.scroll_offset.x < before)
	print("CLOUD_SCROLL_AND_DIMENSIONS_OK")
	camera.enabled = false
	var overview := Camera2D.new()
	overview.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	arena.add_child(overview)
	overview.position = Vector2(0, -24)
	overview.zoom = Vector2(0.30, 0.30)
	overview.make_current()
	player.position = Vector2(0, 204)
	arena.get_node("EntranceStair").visible = true
	arena.get_node("EntranceStair").position = Vector2(0, 254)
	arena.get_node("EntranceStair").scale = Vector2.ONE
	arena.get_node("EntranceStair").modulate = Color.WHITE
	await capture("res://docs/tutorial_arena_layout.png")
	print("TUTORIAL_CHECKS_OK")
	quit()
