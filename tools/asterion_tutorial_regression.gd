extends SceneTree
## Room_1 -> authored arrival -> both tutorial phases -> rewards, without a new exit.
const WARPS: Script = preload("res://scripts/dungeon/ldtk_warps.gd")
const SPEAKER: DialogueSpeaker = preload("res://resources/dialogue/speakers/asterion.tres")
var failures: Array[String] = []
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func wait_until(condition: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/asterion_tutorial"))
	var image: Image = root.get_texture().get_image()
	check(image.save_png("res://output/asterion_tutorial/" + label + ".png") == OK, "Capture saves")


func finish_dialogue(box: DialogueBox) -> void:
	var sequence: DialogueSequence = box.get("_sequence") as DialogueSequence
	for index: int in range(sequence.lines.size() + 2):
		if not box.is_dialogue_active() or box.get("_sequence") != sequence:
			break
		var line: DialogueLine = box.get("_line") as DialogueLine
		if line.speaker != null and line.speaker.display_name == "ASTERION":
			check(box.portrait_texture.texture == SPEAKER.portrait, "Every Asterion line shows the selected portrait")
		box.reveal_current_line()
		box.advance()
		await process_frame


func _run() -> void:
	if rendered:
		root.size = Vector2i(1280, 720)
	check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/maps/open_world.tscn", "Main scene starts in the Room_2 open world")
	check(not bool(WARPS.resolve("res://monster_booster.ldtk", {"TargetScene": "res://../outside.tscn"}).ok), "Scene destination cannot escape the project")
	check(not bool(WARPS.resolve("res://monster_booster.ldtk", {"TargetScene": "res://scenes/missing.tscn"}).ok), "Missing destinations are rejected before departure")
	change_scene_to_file("res://scenes/dungeon/ldtk_arena.tscn")
	await process_frame
	await process_frame
	var room: Node2D = current_scene as Node2D
	check(await wait_until(func() -> bool: return bool(room.get("entry_complete"))), "Room_1 arrival completes")
	var player: Player = room.get_node("Nox") as Player
	var gate: Node2D = null
	for candidate: Node2D in room.get_node("Warps").get("gates"):
		if not str((candidate.get("data") as Dictionary).get("TargetScene", "")).is_empty():
			gate = candidate
	check(gate != null, "Existing Room_1 exit targets the Asterion scene")
	if gate == null:
		quit(1)
		return
	check(not bool(gate.call("can_travel")), "Room_1 exit still requires the spirit horde clear condition")
	room.get_node("Gameplay").call("set_condition", "spirit_horde_1_clear", true)
	player.position = gate.call("spawn_position") as Vector2
	player.health = 30.0
	var old_runtime: CardCombatRuntime = player.get_node("BoosterShooter").get("card_runtime") as CardCombatRuntime
	room.call("_begin_warp_travel", gate)
	check(player.intro_locked, "Departure locks the player for beam and fade")
	var departure_deadline: int = Time.get_ticks_msec() + 5000
	while is_instance_valid(room) and Time.get_ticks_msec() < departure_deadline:
		await process_frame
	check(not is_instance_valid(room), "Departure replaces Room_1")
	var arena: Node2D = current_scene as Node2D
	check(arena.scene_file_path == "res://scenes/tutorial_arena.tscn", "Exit reaches the actual two-stage Asterion tutorial")
	player = arena.get_node("Mox") as Player
	check(player.position.is_equal_approx(Vector2(0, 204)), "Arrival uses the exact former staircase endpoint")
	check(player.intro_locked and not bool(arena.get("entrance_complete")), "Arrival waits for the beam before exploration")
	await create_timer(0.22).timeout
	await capture("arrival_beam")
	check(await wait_until(func() -> bool: return bool(arena.get("entrance_complete"))), "Arrival beam finishes")
	check(player.health == 30.0, "Travel preserves current health")
	check(player.get_node("BoosterShooter").get("card_runtime") == old_runtime, "Travel preserves the equipped card runtime")
	check(not arena.has_node("EntranceStair") and not arena.has_node("EntranceStart"), "Old staircase nodes are removed")
	check((arena.get_node("EntranceWarp") as Sprite2D).position == Vector2(0, 214), "Arrival warp is centered under Nox")
	check(player.floor_height == 0.0, "Arrival warp stays flat")
	var floor_layer: TileMapLayer = arena.get_node("Floor") as TileMapLayer
	var throne_path: TileMapLayer = arena.get_node("ThronePath") as TileMapLayer
	check(floor_layer.tile_set == throne_path.tile_set, "Floor and throne path share the tutorial atlas")
	check((floor_layer.tile_set.get_source(0) as TileSetAtlasSource).texture.resource_path == "res://assets/tiles/floor/floor_tileset2.png", "Tutorial uses floor_tileset2")
	await capture("arrival_floor")
	player.contact_invulnerability = 1000.0
	var boss: Node2D = arena.get_node("MinotaurChair") as Node2D
	var encounter: Node = boss.get_node("TutorialEncounter")
	var box: DialogueBox = boss.get_node("IntroDialogue") as DialogueBox
	var horde: Node2D = encounter.get_node("Horde") as Node2D
	# Shorten only the test's waiting periods; keep real phase transitions and combat deaths.
	boss.set("intro_pause_duration", 0.05)
	encounter.set("weapon_reveal_duration", 0.05)
	horde.set("spawn_duration", 0.4)
	player.position = Vector2(0, -100)
	player.reset_physics_interpolation()
	check(await wait_until(func() -> bool: return box.is_dialogue_active()), "Approaching Asterion starts the current dialogue")
	box.reveal_current_line()
	await process_frame
	check(box.portrait_texture.texture == SPEAKER.portrait and box.portrait_texture.size.x > 0.0, "Portrait fills the existing dialogue slot")
	await capture("portrait_dialogue")
	await finish_dialogue(box)
	check(await wait_until(func() -> bool: return box.is_dialogue_active()), "Weapon reveal resumes the armed dialogue")
	await finish_dialogue(box)
	check(await wait_until(func() -> bool: return int(encounter.get("phase")) == 4), "First phase is the minion horde")
	var completion: Node = encounter.get("completion") as Node
	completion.call("_dismiss_elite_lesson")
	await process_frame
	horde.set("spawning", false)
	var survivors: Array = (horde.get("alive") as Array).duplicate()
	for enemy: Minotaur in survivors:
		enemy.take_damage(enemy.get_current_health())
	check(await wait_until(func() -> bool: return int(encounter.get("phase")) == 5), "Defeating minions enters the return conversation")
	check(float(boss.get("health")) > 0.0, "Asterion remains alive and seated after the minion phase")
	await finish_dialogue(box)
	player.position = boss.get("intro_destination") as Vector2
	player.reset_physics_interpolation()
	check(await wait_until(func() -> bool: return int(encounter.get("phase")) == 6 and box.is_dialogue_active()), "Returning to Asterion opens the challenge dialogue")
	await finish_dialogue(box)
	check(int(encounter.get("phase")) == 7, "Second phase is the Asterion boss fight")
	check(player.health == player.max_health, "Existing boss-phase heal remains intact")
	completion.set_meta(&"elite_explained", true)
	check(await wait_until(func() -> bool: return bool(boss.call("can_receive_damage")), 10.0), "Boss reaches a damageable combat state")
	boss.call("take_damage", 9999.0)
	check(await wait_until(func() -> bool: return box.is_dialogue_active()), "Boss defeat starts surrender dialogue")
	check((box.get("_sequence") as DialogueSequence).sequence_id == &"asterion_surrender", "Victory uses the existing surrender sequence")
	await capture("surrender_portrait")
	await finish_dialogue(box)
	check(await wait_until(func() -> bool: return bool(completion.get("completed")), 12.0), "Existing reward presentation completes")
	check(current_scene == arena and int(encounter.get("phase")) == 9 and not player.intro_locked, "Victory leaves Nox free in the arena, awaiting the future exit")
	check((player.get_meta(&"tutorial_rewards") as Dictionary).get("packs", []).size() == 3, "Three unopened boosters remain awarded")
	check(not completion.has_node("StairDirection") and not arena.has_node("HordePedestals"), "No staircase indicator or future booster pedestal is created")
	await capture("completed_no_exit")
	arena.queue_free()
	await process_frame
	await process_frame
	print("ASTERION_TUTORIAL_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " | failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
