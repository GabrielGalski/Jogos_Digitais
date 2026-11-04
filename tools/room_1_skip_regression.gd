extends SceneTree
## First Tab completes the horde; the following press jumps to Asterion.
const ARENA: PackedScene = preload("res://scenes/dungeon/ldtk_arena.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func ticks(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func tab(echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_TAB
	event.keycode = KEY_TAB
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)


func wait_entry(arena: Node2D) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(arena.get("entry_complete")), "Entry completes normally")


func verify_completion(arena: Node2D, horde: Node2D, pedestal: Node2D) -> void:
	check(int(horde.get("phase")) == 2 and int(horde.get("defeated_count")) == 40, "Tab fulfills all forty eliminations")
	check((horde.get("actors") as Array).is_empty(), "Completion dismisses all remaining spirits")
	check(float(pedestal.get("progress")) == 1.0 and not bool(pedestal.call("can_activate")), "Completion fills the pedestal and prevents activation")
	var rules: Node = arena.get_node("Gameplay")
	check(bool(rules.call("is_condition_met", "spirit_horde_1_clear")), "Exit condition is fulfilled")
	check(bool(rules.call("is_condition_met", "spirit_horde_1_entry_open")), "Entry passage remains open")
	check(not bool(rules.call("is_door_cell_locked", Vector2i(52, 43))), "Exit door opens")
	check(current_scene == arena and not bool(arena.get("_travel_busy")), "Shortcut leaves the player in Room_1")
	var gate: Node2D = (arena.get_node("Warps").get("gates") as Array)[1] as Node2D
	check(bool(gate.call("can_travel")) and gate.has_node("Presentation/Inscriptions"), "Exit warp becomes available with its static yellow markings")
	check(int(arena.get_node("EnemyRemains").call("total_count")) == 0, "Skipping does not create forty fake corpse effects")


func _run() -> void:
	for active: bool in [false, true]:
		var arena: Node2D = ARENA.instantiate() as Node2D
		root.add_child(arena)
		current_scene = arena
		var horde: Node2D = (arena.get_node("SpiritHordes").get("encounters") as Array)[0] as Node2D
		var pedestal: Node2D = (arena.get_node("HordePedestals").get("pedestals") as Array)[0] as Node2D
		if active:
			await wait_entry(arena)
			horde.call("begin")
			check((horde.get("actors") as Array).size() >= 12, "Active-case test contains real enemies")
		else:
			check(int(horde.get("phase")) == 0, "Waiting-case pedestal has never been activated")
		tab(true)
		await ticks(2)
		check(int(horde.get("defeated_count")) == 0, "Keyboard-repeat events cannot trigger the skip")
		tab()
		if not active:
			check(not bool(arena.get("entry_complete")), "Early Tab does not cancel the arrival cutscene")
			await wait_entry(arena)
		await ticks()
		verify_completion(arena, horde, pedestal)
		tab()
		var deadline: int = Time.get_ticks_msec() + 8000
		while is_instance_valid(arena) and Time.get_ticks_msec() < deadline:
			await process_frame
		check(not is_instance_valid(arena) and current_scene.scene_file_path == SceneJumper.ASTERION_SCENE, "The next fresh Tab jumps from the completed horde to Asterion")
		current_scene.queue_free()
		await ticks()
	print("ROOM_1_SKIP_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " | failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
