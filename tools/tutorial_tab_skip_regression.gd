extends SceneTree
## First Tab reaches Asterion; the next fresh press returns to the open map.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _tab(echo: bool = false) -> void:
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_TAB
	press.keycode = KEY_TAB
	press.pressed = true
	press.echo = echo
	Input.parse_input_event(press)
	var release: InputEventKey = press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)


func _run() -> void:
	root.size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	var arena: Node2D = current_scene as Node2D
	var boss: Node2D = arena.get_node("MinotaurChair") as Node2D
	var encounter: Node = boss.get_node("TutorialEncounter")
	var crosshair: Sprite2D = arena.get_node_or_null("ArenaUI/Crosshair") as Sprite2D
	_check(is_instance_valid(crosshair) and crosshair.texture != null and crosshair.scale.is_equal_approx(Vector2.ONE * 0.5), "Tutorial reticle is missing or incorrectly scaled")
	_tab()
	await process_frame
	_check(bool(encounter.get("skip_requested")), "First Tab did not request the existing boss skip")
	await create_timer(1.7).timeout
	_check(int(encounter.get("phase")) == 7, "First Tab starts the boss after arrival")
	_tab(true)
	await process_frame
	_check(current_scene == arena, "Keyboard repeat does not leave the boss phase")
	_tab()
	var deadline: int = Time.get_ticks_msec() + 12000
	while current_scene == arena and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(current_scene != null and current_scene.scene_file_path == SceneJumper.WORLD_SCENE, "The next Tab returns to the open world without the merchant")
	print("TUTORIAL TAB SKIP: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
