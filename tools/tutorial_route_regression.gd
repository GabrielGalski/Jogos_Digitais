extends SceneTree
## Exercises the tutorial camera, dialogue, M01, and both merchant-hall exits.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	var arena: Node2D = current_scene as Node2D
	_check(is_instance_valid(arena) and arena.name == "TutorialArena", "Game did not start in the tutorial")
	if not is_instance_valid(arena):
		_finish()
		return
	var player: Player = arena.get_node("Mox") as Player
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	var boss: Node2D = arena.get_node("MinotaurChair") as Node2D
	var encounter: Node = boss.get_node("TutorialEncounter")
	var weapon: Node2D = player.get_node("BoosterShooter") as Node2D
	_check(camera.is_current() and camera.zoom.is_equal_approx(Vector2.ONE * 0.95), "Tutorial camera does not match combat-room framing")
	_check(camera.position_smoothing_enabled, "Tutorial camera lost the combat-room follow smoothing")
	_check(is_equal_approx(player.movement_speed, 94.3), "Tutorial Nox speed differs from combat room")
	_check(bool(weapon.get("use_m01_projectile")), "Tutorial shooter did not select M01 visuals")
	var runtime: CardCombatRuntime = weapon.get("card_runtime") as CardCombatRuntime
	_check(runtime._loadout.manifestation.card_id == &"M01", "Tutorial did not equip the M01 card")
	var entry_camera_position: Vector2 = camera.global_position
	await create_timer(0.45).timeout
	_check(camera.top_level and camera.global_position.distance_to(entry_camera_position) < 1.0, "Camera moved during the entrance cutscene")
	await create_timer(2.25).timeout
	_check(bool(arena.get("entrance_complete")) and not camera.top_level, "Entrance did not restore the following camera")
	player.position = Vector2(0.0, -100.0)
	player.reset_physics_interpolation()
	await create_timer(0.8).timeout
	_check(camera.get_screen_center_position().y < 30.0, "Camera did not follow Nox toward the throne")
	await create_timer(3.5).timeout
	var dialogue: DialogueBox = boss.get_node("IntroDialogue") as DialogueBox
	_check(dialogue.is_dialogue_active(), "Asterion's intro dialogue did not open")
	_check(camera.is_current() and camera.zoom.is_equal_approx(Vector2.ONE * 0.95), "Dialogue changed the camera framing")
	_check(not camera.top_level, "Dialogue left the entrance camera detached")
	var player_on_screen: Vector2 = root.get_canvas_transform() * player.global_position
	var boss_on_screen: Vector2 = root.get_canvas_transform() * boss.global_position
	_check(Rect2(Vector2.ZERO, root.size).has_point(player_on_screen), "Dialogue camera cropped Nox")
	_check(Rect2(Vector2.ZERO, root.size).has_point(boss_on_screen), "Dialogue camera cropped Asterion")
	encounter.call("skip_to_boss")
	await create_timer(1.35).timeout
	_check(not dialogue.is_dialogue_active(), "Skipping the dialogue left its overlay active")
	_check(camera.is_current() and camera.zoom.is_equal_approx(Vector2.ONE * 0.95), "Boss cutscene changed the camera zoom")
	_check(is_zero_approx(camera.rotation) and camera.ignore_rotation, "Boss cutscene did not restore camera rotation")
	_check(not player.intro_locked, "Boss cutscene did not unlock Nox for combat")
	var shot: Node2D = weapon.call("fire_once") as Node2D
	_check(is_instance_valid(shot) and shot.get("mode") == &"M01", "Tutorial fired the old projectile instead of M01")
	if is_instance_valid(shot):
		_check(shot.is_in_group(&"player_projectiles"), "M01 will not be cleaned up by tutorial completion")
	_check(camera.is_current() and camera.zoom.is_equal_approx(Vector2.ONE * 0.95), "Firing changed the tutorial camera")

	arena.set("exit_available", true)
	arena.call("leave_tutorial")
	await create_timer(1.85).timeout
	_check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/merchant_corridor.tscn", "Tutorial exit did not fade into merchant hall")
	if current_scene.scene_file_path != "res://scenes/merchant_corridor.tscn":
		_finish()
		return
	var hall: Node2D = current_scene as Node2D
	await create_timer(2.5).timeout
	_check(int(hall.get("state")) == 2, "Merchant hall entrance did not finish")
	_check((hall.get_node("FadeLayer/Fade") as ColorRect).color.a < 0.01, "Merchant hall did not fade in")
	_check((hall.get_node("World/Entrance/DoorPanel") as Node2D).visible, "Merchant hall entrance door did not close")
	var dungeon_door: Button = hall.get_node("World/DungeonDoorButton") as Button
	_check(not dungeon_door.disabled, "Merchant combat-room door remained disabled")
	dungeon_door.emit_signal(&"pressed")
	await create_timer(0.65).timeout
	_check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/dungeon/merchant_platform.tscn", "Merchant door did not reach the combat room")
	if current_scene.scene_file_path == "res://scenes/dungeon/merchant_platform.tscn":
		await create_timer(0.55).timeout
		_check((current_scene.get_node("Transition/Fade") as ColorRect).color.a < 0.01, "Combat room did not fade in")

	change_scene_to_file("res://scenes/merchant_corridor.tscn")
	await create_timer(2.5).timeout
	hall = current_scene as Node2D
	_check(int(hall.get("state")) == 2, "Merchant hall was not playable on second entry")
	# Ground X includes the hall's depth skew; projected X must cross 912.
	hall.set("ground_position", Vector2(930.0, 28.0))
	hall.call("_update_player", 0.016)
	await create_timer(0.7).timeout
	_check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/dungeon/ldtk_arena.tscn", "Right-hand hall exit did not reach its LDtk arena")
	_finish()


func _finish() -> void:
	print("TUTORIAL ROUTE REGRESSION: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
