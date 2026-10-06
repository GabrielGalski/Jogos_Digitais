extends SceneTree

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("HALL SHOOTER: " + message)

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
	var hall: Node2D = current_scene as Node2D
	var nox: Node2D = hall.get_node("Nox") as Node2D
	var shooter: Node2D = hall.get_node("HallShooter") as Node2D
	var face: Sprite2D = shooter.get_node("Face") as Sprite2D
	_check(shooter.visible and face.texture != null, "present from scene start")
	_check(shooter.z_index < nox.z_index, "always behind Nox")
	_check(face.material is ShaderMaterial, "existing edge filter reused")
	await create_timer(2.3).timeout
	_check(shooter.global_position.y < nox.global_position.y - 20.0, "hovers above Nox")
	var idle_y: float = shooter.global_position.y
	await create_timer(0.3).timeout
	_check(absf(shooter.global_position.y - idle_y) > 0.05, "idle hover animates")
	_key(KEY_D, true)
	await create_timer(1.1).timeout
	_key(KEY_D, false)
	_check(int(hall.get("floor_level")) == 0, "Nox still descends stairs")
	_check(shooter.global_position.distance_to(nox.global_position) < 90.0, "follows across staircase")
	_check(shooter.global_position.x < nox.global_position.x, "trails on left when moving right")
	_key(KEY_A, true)
	await create_timer(0.5).timeout
	_key(KEY_A, false)
	await create_timer(0.5).timeout
	_check(shooter.global_position.x > nox.global_position.x, "smoothly changes shoulder on reversal")
	root.warp_mouse(root.get_canvas_transform() * (shooter.global_position + Vector2(-80, 0)))
	await physics_frame
	await physics_frame
	_check(face.texture.resource_path.ends_with("look_left.png"), "eyes follow mouse")
	hall.set("ground_position", Vector2(338.0, 16.0))
	await create_timer(0.5).timeout
	_key(KEY_E, true)
	_key(KEY_E, false)
	await create_timer(0.2).timeout
	var dialogue: DialogueBox = hall.get_node("TinDialogue") as DialogueBox
	_check(dialogue.is_dialogue_active(), "Tin interaction preserved")
	var talk_y: float = shooter.global_position.y
	await create_timer(0.3).timeout
	_check(shooter.visible and absf(shooter.global_position.y - talk_y) > 0.05, "hover continues during dialogue")
	dialogue.close_dialogue()
	await create_timer(0.3).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://renders/merchant_with_shooter.png")
	_check(get_nodes_in_group(&"player_projectiles").is_empty(), "safe room has no projectiles")
	hall.set("ground_position", Vector2(952.0, 28.0))
	await create_timer(1.4).timeout
	_check(current_scene.name == "DungeonPreview", "exit transition preserved")
	_check(not current_scene.has_node("HallShooter"), "hall follower does not leak into combat")
	_check(current_scene.has_node("Nox/BoosterShooter/DeckBox"), "original combat caster remains available")
	print("HALL SHOOTER REVIEW: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
