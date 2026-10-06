extends SceneTree

var failures: int = 0
var shooter: Node2D
var hall: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("ENTRANCE/LOOK: " + message)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://renders/" + label + ".png")

func _cursor(offset: Vector2) -> void:
	root.warp_mouse(root.get_canvas_transform() * (shooter.global_position + offset))
	await physics_frame
	await physics_frame
	await process_frame

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 540)
	change_scene_to_file("res://scenes/merchant_corridor.tscn")
	await process_frame
	await process_frame
	hall = current_scene as Node2D
	shooter = hall.get_node("HallShooter") as Node2D
	var nox: Node2D = hall.get_node("Nox") as Node2D
	var layer: Node2D = hall.get_node("EntranceCutscene") as Node2D
	var overlay: Sprite2D = layer.get_node("HallOverlay") as Sprite2D
	var face: Sprite2D = shooter.get_node("Face") as Sprite2D
	var art: Image = overlay.texture.get_image()
	_check(overlay.position == Vector2(-32, -32) and art.get_size() == Vector2i(151, 334), "overlay aligns exactly with hall")
	_check(art.get_pixel(30, 100).a == 0.0 and art.get_pixel(10, 100).a == 1.0, "door alpha remains intact")
	_check(layer.visible and bool(layer.get("active")), "dedicated entrance layer active")
	_check(nox.z_index < overlay.z_index and shooter.z_index < overlay.z_index, "both start behind aperture")
	_check(not bool(shooter.get("mouse_look_enabled")), "cutscene controls facing")
	await create_timer(0.7).timeout
	await _capture("merchant_entrance_aperture")
	await create_timer(0.35).timeout
	_check(nox.z_index > overlay.z_index and shooter.z_index < overlay.z_index, "Nox emerges before trailing shooter")
	await _capture("merchant_entrance_emerging")
	await create_timer(1.2).timeout
	_check(int(hall.get("state")) == 2 and not layer.visible, "entrance finishes and gameplay resumes")
	_check(nox.z_index == 10 and shooter.z_index == 9, "gameplay layering restored")
	_check(bool(shooter.get("mouse_look_enabled")), "mouse look enabled after entrance")
	hall.set("ground_position", Vector2(338.0, 28.0))
	await create_timer(0.4).timeout
	await _cursor(Vector2(-80, 0))
	_check(face.texture.resource_path.ends_with("look_left.png"), "eyes look left")
	await _cursor(Vector2(80, 0))
	_check(face.texture.resource_path.ends_with("look_right.png"), "eyes look right")
	await _cursor(Vector2(0, 70))
	_check(face.texture.resource_path.ends_with("looking_straight.png"), "eyes centered")
	await _capture("merchant_shooter_cursor_front")
	_key(KEY_W, true)
	await create_timer(0.1).timeout
	_key(KEY_W, false)
	await _cursor(Vector2(80, 0))
	_check(face.texture.resource_path.ends_with("back.png"), "mouse cannot overwrite back pose")
	await _cursor(Vector2(-80, 0))
	_check(face.texture.resource_path.ends_with("back.png"), "back pose remains while stationary")
	await _capture("merchant_shooter_back_preserved")
	_key(KEY_S, true)
	await create_timer(0.1).timeout
	_key(KEY_S, false)
	await _cursor(Vector2(80, 0))
	_check(face.texture.resource_path.ends_with("look_right.png"), "eyes resume after facing forward")
	_check(float(hall.get("movement_speed")) == 112.5 and int(hall.get("floor_level")) == 0, "speed and level logic preserved")
	print("ENTRANCE/LOOK REVIEW: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
