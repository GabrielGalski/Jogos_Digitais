extends SceneTree
## Ghost tutorial totem, actual combat, authored doors and exit warp.
const ARENA: String = "res://scenes/dungeon/ldtk_arena.tscn"
var failures: Array[String] = []
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func place(player: Player, feet: Vector2) -> void:
	player.position = feet - Vector2(0, 3)
	player.snap_floor_height()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()


func wait_entry(arena: Node2D) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(arena.get("entry_complete")), "Arrival completes")


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/pedestal"))
	var image: Image = root.get_texture().get_image()
	check(image.save_png("res://output/pedestal/" + label + ".png") == OK, "Capture saves")
func _run() -> void:
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	var arena: Node2D = (load(ARENA) as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	await wait_entry(arena)
	var player: Player = arena.get_node("Nox") as Player
	var horde: Node2D = (arena.get_node("SpiritHordes").get("encounters") as Array)[0] as Node2D
	var pedestals: Array = arena.get_node("HordePedestals").get("pedestals") as Array
	check(pedestals.size() == 1, "Room_1 contains one authored pedestal")
	if pedestals.is_empty():
		quit(1)
		return
	var pedestal: Node2D = pedestals[0] as Node2D
	var opener: Node2D = pedestal.get_node("BoosterOpener") as Node2D
	var action: Sprite2D = pedestal.get_node("ActionPrompt") as Sprite2D
	var marker: Node2D = opener.get_node("Visuals/ExclamationMarker") as Node2D
	var warning: Node2D = opener.get_node("Visuals/CombatWarning") as Node2D
	check(not pedestal.has_node("Plate") and not pedestal.has_node("WhiteCirculation"), "Tutorial uses only the new machine")
	check(bool(arena.call("is_ground_surface_point", pedestal.global_position)), "Tutorial keeps its ground support")
	var exit_gate: Node2D = (arena.get_node("Warps").get("gates") as Array)[1] as Node2D
	var exit_action: Sprite2D = exit_gate.get_node("ActionPrompt") as Sprite2D
	check(exit_action.get_script() == action.get_script(), "Exit warp and pedestal share the same white animated action")
	place(player, (exit_gate.call("spawn_position") as Vector2) + Vector2(0, 3))
	await ticks(2)
	check(not exit_action.visible and not bool(exit_gate.call("can_interact")), "Locked exit never advertises an unavailable E interaction")
	place(player, pedestal.global_position + Vector2(96, 0))
	await ticks(2)
	key(KEY_E, true)
	await ticks(1)
	key(KEY_E, false)
	check(int(horde.get("phase")) == 0 and not action.visible and marker.visible, "Distant E does not start the encounter")
	place(player, pedestal.global_position + Vector2(0, 32))
	await ticks(3)
	check(action.visible and not marker.visible, "Approach replaces the exclamation with E")
	key(KEY_E, true, true)
	await ticks(1)
	key(KEY_E, false)
	check(int(horde.get("phase")) == 0, "Keyboard repeat cannot activate the totem")
	key(KEY_E, true)
	await ticks(2)
	key(KEY_E, false)
	check(int(horde.get("phase")) == 1 and not (horde.get("actors") as Array).is_empty(), "Fresh E starts the existing spirit encounter")
	check(warning.visible and not action.visible, "Combat warning replaces the prompt")
	var entry_cells: Array = (arena.get_node("Gameplay/DoorBlocks").get("_named_regions") as Dictionary).get("spirit_entry", []) as Array
	check(not entry_cells.is_empty(), "Authored tutorial entry has door cells")
	for cell: Vector2i in entry_cells:
		check(bool(arena.get_node("Gameplay").call("is_door_cell_locked", cell)), "Pedestal activation seals the authored entry")
	horde.set_physics_process(false)
	place(player, pedestal.global_position + Vector2(48, 0))
	await ticks(3)
	for count: int in range(1, int(horde.get("kill_target")) + 1):
		var actors: Array = horde.get("actors") as Array
		var ghost: Node2D = actors[0] as Node2D if not actors.is_empty() else horde.call("_spawn_one") as Node2D
		check(warning.visible, "Warning stays visible for every combat kill")
		ghost.call("take_damage", 1000.0)
	check(int(horde.get("phase")) == 2 and not warning.visible, "Final kill turns off the warning")
	await ticks(85)
	check(str(opener.get("state")) == "opened" and (opener.get_node("Visuals/Cards/Center") as Sprite2D).visible, "Tutorial victory reveals the cards on approach")
	check(not bool(arena.get_node("Gameplay").call("is_door_cell_locked", Vector2i(52, 43))), "Completed horde opens the exit")
	key(KEY_E, true)
	await ticks(2)
	key(KEY_E, false)
	check(int(horde.get("phase")) == 2, "Completed pedestal cannot restart its own horde")
	check(not action.visible and not marker.visible, "Cleared machine has no activation prompt")
	place(player, (exit_gate.call("spawn_position") as Vector2) + Vector2(0, 3))
	await ticks(2)
	check(exit_action.visible and bool(exit_gate.call("can_interact")), "Cleared exit shows E only when the player stands on its surface")
	await capture("exit_action")
	var exit_hint_y: float = exit_action.position.y
	await ticks(17)
	check(exit_action.position.y != exit_hint_y and absf(exit_action.position.y - exit_hint_y) <= 4.0, "Exit E moves within its four-pixel vertical span")
	await capture("exit_action_bob")
	place(player, exit_gate.global_position + Vector2(40, 0))
	await ticks(2)
	check(not exit_action.visible, "Leaving the unlocked exit hides E")
	place(player, (exit_gate.call("spawn_position") as Vector2) + Vector2(0, 3))
	await ticks(2)
	check(exit_action.visible, "Returning to the unlocked exit restores E")
	key(KEY_E, true)
	await ticks(2)
	key(KEY_E, false)
	check(not exit_action.visible, "Warp departure hides its action during the beam and fade")
	var deadline: int = Time.get_ticks_msec() + 5000
	while is_instance_valid(arena) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(arena), "Exit replaces Room_1 after pedestal completion")
	var fresh: Node2D = current_scene as Node2D
	if is_instance_valid(fresh):
		check(fresh.scene_file_path == "res://scenes/tutorial_arena.tscn", "Cleared exit reaches the Asterion tutorial")
		var arrival_deadline: int = Time.get_ticks_msec() + 4000
		while not bool(fresh.get("entrance_complete")) and Time.get_ticks_msec() < arrival_deadline:
			await process_frame
		check((fresh.get_node("Mox") as Player).floor_height == 0.0, "Asterion arrival warp stays flat")
		fresh.queue_free()
	await ticks(3)
	print("PEDESTAL_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " | failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
