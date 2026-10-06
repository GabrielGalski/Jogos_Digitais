extends SceneTree
## Three physical Tab presses reach the boss, hall, then the corridor-end arena.

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
	var crosshair: Sprite2D = encounter.get_node_or_null("CombatAim/Crosshair") as Sprite2D
	_check(is_instance_valid(crosshair) and crosshair.texture != null and crosshair.scale.is_equal_approx(Vector2.ONE * 0.5), "Tutorial reticle is missing or incorrectly scaled")
	_tab()
	await process_frame
	_check(bool(encounter.get("skip_requested")), "First Tab did not request the existing boss skip")
	paused = true
	_check(not (encounter.get_node("Horde") as Node).can_process(), "Tutorial combat continued while an overlay paused the game")
	_tab()
	await process_frame
	await process_frame
	_check(bool(encounter.get("completion").get("completed")), "Second Tab did not start merchant transition")
	_check(not paused, "Second Tab left tutorial UI paused")
	await create_timer(0.85).timeout
	_check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/merchant_corridor.tscn", "Second Tab did not fade into merchant hall")
	_tab(true)
	await process_frame
	_check(not bool(current_scene.get("restart_started")), "Held Tab incorrectly skipped the merchant hall")
	_tab()
	await process_frame
	_check(bool(current_scene.get("restart_started")), "Third Tab did not request the corridor-end jump")
	_tab()
	await create_timer(0.7).timeout
	_check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://scenes/dungeon/ldtk_arena.tscn", "Third Tab did not reach the existing corridor-end scene")
	print("TUTORIAL TAB SKIP: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
