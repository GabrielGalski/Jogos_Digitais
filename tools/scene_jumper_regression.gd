extends SceneTree
## Input-driven loop: world -> spirit skip -> Asterion skip -> world, plus F6 fallback.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)


func ticks(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func tab(echo: bool = false, logical_only: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_NONE if logical_only else KEY_TAB
	event.keycode = KEY_TAB
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)


func wait_until(condition: Callable, seconds: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())


func at_scene(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path


func _run() -> void:
	change_scene_to_file(SceneJumper.WORLD_SCENE)
	await process_frame
	await process_frame
	var world: Node2D = current_scene as Node2D
	check(at_scene(SceneJumper.WORLD_SCENE), "The test starts in the actual open map")
	var world_player: Player = world.get_node("Nox") as Player
	world_player.health = world_player.max_health * 0.5
	var saved_health: float = world_player.health
	var runtime: CardCombatRuntime = world_player.get_node("BoosterShooter").get("card_runtime") as CardCombatRuntime
	tab(true)
	await ticks()
	check(current_scene == world and not bool(world.get("_completion_skip_requested")), "Keyboard repeat does not jump")
	tab()
	await ticks(1)
	check(current_scene == world, "An early Tab waits for arrival and the normal departure fade")
	check(await wait_until(func() -> bool: return at_scene(SceneJumper.SPIRIT_SCENE)), "Map Tab reaches the ghost tutorial")
	var spirits: Node2D = current_scene as Node2D
	check(await wait_until(func() -> bool: return bool(spirits.get("entry_complete"))), "Spirit arrival completes")
	check(not is_instance_valid(world), "The previous map is released")
	var ghost_player: Player = spirits.get_node("Nox") as Player
	check(is_equal_approx(ghost_player.health, saved_health), "Jump travel preserves player health")
	check(ghost_player.get_node("BoosterShooter").get("card_runtime") == runtime, "Jump travel preserves equipped cards")
	var horde: Node2D = (spirits.get_node("SpiritHordes").get("encounters") as Array)[0] as Node2D
	check(int(horde.get("defeated_count")) == 0, "The ghost tutorial starts fresh")
	tab()
	await ticks(5)
	check(current_scene == spirits and int(horde.get("defeated_count")) == 40, "The first spirit Tab preserves the forty-kill skip")
	check(bool(spirits.get_node("Gameplay").call("is_condition_met", "spirit_horde_1_clear")), "The skip still opens the passage")
	tab(true)
	await ticks()
	check(current_scene == spirits and not bool(spirits.get("_travel_busy")), "Holding Tab cannot skip two steps")
	tab(false, true)
	check(await wait_until(func() -> bool: return at_scene(SceneJumper.ASTERION_SCENE)), "The next spirit Tab reaches Asterion without walking to the exit")
	var asterion: Node2D = current_scene as Node2D
	var encounter: Node = asterion.get_node("MinotaurChair/TutorialEncounter")
	tab()
	await ticks()
	check(bool(encounter.get("skip_requested")) or int(encounter.get("phase")) == 7, "Asterion's original boss skip remains available during arrival")
	check(await wait_until(func() -> bool: return int(encounter.get("phase")) == 7), "The first Asterion Tab starts its existing boss phase")
	check(current_scene == asterion, "The boss skip does not immediately leave the tutorial")
	tab(true)
	await ticks()
	check(current_scene == asterion and not bool(asterion.get("_world_jump_requested")), "Asterion also ignores keyboard repeat")
	tab()
	check(await wait_until(func() -> bool: return at_scene(SceneJumper.WORLD_SCENE)), "The next Asterion Tab returns to the open map")
	var returned: Node2D = current_scene as Node2D
	check(await wait_until(func() -> bool: return bool(returned.get("entry_complete"))), "Return arrival completes")
	var returned_player: Player = returned.get_node("Nox") as Player
	var return_gate: Node2D = returned.get("_arrival_gate") as Node2D
	check(returned_player.displayed_height == float(return_gate.get_node("Platform").get("elevation")), "Return uses the elevated central warp")
	check(returned_player.get_node("BoosterShooter").get("card_runtime") == runtime, "The loop preserves the equipped runtime")
	check(not paused and is_equal_approx(Engine.time_scale, 1.0), "The return has normal time and is unpaused")
	check(get_nodes_in_group(&"scene_jump_controllers").size() == 1, "Only the active scene owns a jump controller")
	returned.queue_free()
	await process_frame
	var preview: Node2D = Node2D.new()
	preview.name = "UnregisteredF6Preview"
	root.add_child(preview)
	current_scene = preview
	paused = true
	Engine.time_scale = 0.12
	tab()
	check(await wait_until(func() -> bool: return at_scene(SceneJumper.WORLD_SCENE)), "Scenes without a local skip return to the map even when paused")
	check(not paused and is_equal_approx(Engine.time_scale, 1.0), "Fallback clears old pause and slow motion")
	check(not is_instance_valid(preview), "Fallback releases the outgoing preview")
	print("SCENE_JUMPER_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	current_scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
