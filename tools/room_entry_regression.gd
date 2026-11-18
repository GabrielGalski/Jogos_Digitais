extends SceneTree
## Reach the authored central pedestal from the actual spawn without teleporting through doors.
const ARENA: PackedScene = preload("res://scenes/dungeon/ldtk_arena.tscn")
var failures: Array[String] = []
var _keys: Dictionary[Key, bool] = {}


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)


func key(code: Key, pressed: bool) -> void:
	if bool(_keys.get(code, false)) == pressed:
		return
	_keys[code] = pressed
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func walk(player: Player, target: Vector2) -> void:
	var frames: int = ceili(player.position.distance_to(target) / player.movement_speed * 60.0) + 90
	for frame: int in range(frames):
		var offset: Vector2 = target - player.position
		key(KEY_A, offset.x < -1.5)
		key(KEY_D, offset.x > 1.5)
		key(KEY_W, offset.y < -1.5)
		key(KEY_S, offset.y > 1.5)
		if offset.length_squared() < 5.0:
			break
		await physics_frame
	for code: Key in [KEY_A, KEY_D, KEY_W, KEY_S]:
		key(code, false)
	check(player.position.distance_to(target) < 4.0, "Player must physically reach waypoint %s; actual=%s" % [target, player.position])


func _run() -> void:
	var arena: Node2D = ARENA.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	var deadline: int = Time.get_ticks_msec() + 4000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	var player: Player = arena.get_node("Nox") as Player
	var rules: Node2D = arena.get_node("Gameplay") as Node2D
	var horde: Node2D = (arena.get_node("SpiritHordes").get("encounters") as Array)[0] as Node2D
	var pedestal: Node2D = (arena.get_node("HordePedestals").get("pedestals") as Array)[0] as Node2D
	check(not bool(rules.call("is_door_cell_locked", Vector2i(28, 58))), "Entry passage is open on startup")
	check(bool(rules.call("is_door_cell_locked", Vector2i(52, 43))), "Exit waits for the completed horde")
	check(int(horde.get("phase")) == 0 and not bool(horde.get("activate_on_enter")), "Room waits for E on pedestal")
	if bool(rules.call("is_door_cell_locked", Vector2i(28, 58))):
		arena.queue_free()
		await process_frame
		print("ROOM_ENTRY_REGRESSION FAIL | startup is blocked")
		quit(1)
		return
	await walk(player, Vector2(264, 925))
	await walk(player, Vector2(512, 925))
	await walk(player, Vector2(512, pedestal.position.y - 3))
	await walk(player, pedestal.position - Vector2(36, 3))
	await walk(player, pedestal.position - Vector2(0, 3))
	for frame: int in range(5):
		await physics_frame
	check(player.floor_height == 4.0 and bool(pedestal.call("can_activate")), "Central pedestal is accessible from the surrounding floor")
	check(int(horde.get("phase")) == 0, "Walking the entire route does not activate the encounter")
	key(KEY_E, true)
	await physics_frame
	await physics_frame
	key(KEY_E, false)
	check(int(horde.get("phase")) == 1, "E begins combat after the player reaches the pedestal normally")
	check(bool(rules.call("is_door_cell_locked", Vector2i(28, 58))), "Entry seals only after activation")
	arena.queue_free()
	await process_frame
	await process_frame
	print("ROOM_ENTRY_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " | failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
