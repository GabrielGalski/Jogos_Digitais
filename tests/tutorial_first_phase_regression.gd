extends SceneTree

func _initialize() -> void:
	call_deferred(&"run")

func finish_dialogue(box: DialogueBox) -> void:
	for index: int in range(20):
		if not box.is_dialogue_active():
			return
		box.reveal_current_line()
		box.advance()
		await process_frame

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node = main.get_node("TutorialArena")
	var boss: Node = arena.get_node("MinotaurChair")
	var encounter: Node = boss.tutorial_encounter
	await arena.entrance_finished
	boss._begin_player_approach()
	for frame: int in range(600):
		await physics_frame
		if encounter.dialogue.is_dialogue_active():
			break
	assert(encounter.dialogue.is_dialogue_active())
	await finish_dialogue(encounter.dialogue)
	for frame: int in range(120):
		await physics_frame
		if encounter.dialogue.is_dialogue_active():
			break
	await finish_dialogue(encounter.dialogue)
	encounter.horde.spawn_duration = 0.25
	for frame: int in range(500):
		await physics_frame
		if encounter.phase == encounter.Phase.HORDE:
			break
	assert(encounter.phase == encounter.Phase.HORDE)
	assert(encounter.weapon.combat_enabled)
	for frame: int in range(20):
		await physics_frame
	assert(not encounter.horde.spawning)
	var survivors: Array = encounter.horde.alive.duplicate()
	for mob: Minotaur in survivors:
		mob.take_damage(mob.resistance)
	await physics_frame
	await physics_frame
	assert(encounter.phase == encounter.Phase.RETURN)
	encounter.player.position = boss.intro_destination
	for frame: int in range(300):
		await physics_frame
		if encounter.phase == encounter.Phase.CHALLENGE:
			break
	assert(encounter.phase == encounter.Phase.CHALLENGE)
	await finish_dialogue(encounter.dialogue)
	assert(encounter.phase == encounter.Phase.BOSS)
	assert(encounter.player.health == 60)
	for frame: int in range(350):
		await physics_frame
		if encounter.elite_horde_started:
			break
	assert(encounter.elite_horde_started)
	print("TUTORIAL_FIRST_PHASE_OK")
	quit()
