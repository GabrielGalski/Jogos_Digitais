extends SceneTree
## Production keeps only Equilibrado, with a 30% smaller light and no Backspace selector.
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	var packed: PackedScene = load("res://scenes/dungeon/ldtk_arena.tscn") as PackedScene
	var arena: Node2D = packed.instantiate() as Node2D
	root.add_child(arena)
	await process_frame
	var lighting: CanvasLayer = arena.get_node("RoomLighting") as CanvasLayer
	var profile: Resource = lighting.get("profile") as Resource
	_check(int(lighting.call("setup_count")) == 1, "Only one lighting setup must be active")
	_check(str(lighting.call("setup_name")) == "Equilibrado" and not bool(lighting.call("can_cycle_setups")), "Equilibrado must be fixed")
	_check(is_equal_approx(float(profile.get("radius")),44.0*0.7), "Base radius must be 30 percent smaller")
	_check(not (lighting.get_node("SetupHintMargin/SetupHint") as Label).visible, "Do not show a selector for a single setup")
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_BACKSPACE
	event.keycode = KEY_BACKSPACE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var release: InputEventKey = event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	_check(str(lighting.call("setup_name")) == "Equilibrado", "Backspace must not switch lighting")
	arena.queue_free()
	await process_frame
	print(JSON.stringify({"ok":_failures.is_empty(),"failures":_failures}))
	quit(0 if _failures.is_empty() else 1)
