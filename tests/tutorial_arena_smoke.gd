extends SceneTree

func _initialize() -> void:
	call_deferred(&"run_checks")

func capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
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
	assert(player.position == Vector2(0, 424))
	await create_timer(0.9).timeout
	assert(player.position.y < 424 and player.position.y > 284)
	await capture("res://.godot/tutorial_arrival.png")
	await arena.entrance_finished
	assert(player.position.is_equal_approx(Vector2(0, 284)))
	assert(not player.intro_locked)
	assert(not arena.get_node("EntranceStair").visible)
	assert(not camera.top_level and camera.is_current())
	assert(camera.limit_top == -836)
	assert(camera.limit_bottom == -68)
	print("INTRO_OK destination=", player.position, " stair hidden, input restored")
	await capture("res://.godot/tutorial_after_intro.png")
	var right := await move_for(player, Vector2(280, 200), KEY_D, 60)
	assert(right.x > 315 and right.x <= 316)
	var down := await move_for(player, Vector2(0, 284), KEY_S, 60)
	assert(down.y > 311 and down.y <= 312)
	var up := await move_for(player, Vector2(80, -340), KEY_W, 60)
	assert(up.y < -380 and up.y >= -382)
	print("BOUNDARIES_OK right=", right, " bottom=", down, " top=", up)
	var behind := await move_for(player, Vector2(-40, -330), KEY_D, 60)
	assert(behind.x > 35)
	var seat := await move_for(player, Vector2(0, -250), KEY_W, 60)
	assert(seat.y > -289 and seat.y < -270)
	print("THRONE_OK back passage=", behind, " base blocks at=", seat)
	player.position = Vector2(0, -330)
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
	var points := [Vector2(0, 284), Vector2(0, 216), Vector2(32, 216), Vector2(32, 152), Vector2(0, 152), Vector2(0, -120), Vector2(-48, -120), Vector2(-48, -200), Vector2(0, -200), Vector2(0, -265)]
	walker.position = points[0]
	await physics_frame
	for i in range(points.size()-1):
		var hit := walker.move_and_collide(points[i+1] - walker.position)
		assert(hit == null, "Path intersects a collider")
	walker.queue_free()
	print("PATH_TRAVERSAL_OK")
	camera.enabled = false
	var overview := Camera2D.new()
	overview.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	arena.add_child(overview)
	overview.position = Vector2(0, -24)
	overview.zoom = Vector2(0.30, 0.30)
	overview.make_current()
	player.position = Vector2(0, 284)
	arena.get_node("EntranceStair").visible = true
	arena.get_node("EntranceStair").position = Vector2(0, 334)
	arena.get_node("EntranceStair").scale = Vector2.ONE
	arena.get_node("EntranceStair").modulate = Color.WHITE
	await capture("res://docs/tutorial_arena_layout.png")
	print("TUTORIAL_CHECKS_OK")
	quit()
