extends SceneTree

func _initialize() -> void:
	call_deferred(&"run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node = main.get_node("TutorialArena")
	var boss: Node = arena.get_node("MinotaurChair")
	await arena.entrance_finished
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_TAB
	key.pressed = true
	Input.parse_input_event(key)
	for frame: int in range(15):
		await physics_frame
	assert(boss.tutorial_encounter.phase == boss.tutorial_encounter.Phase.BOSS)
	assert(boss.player.get_node("BoosterShooter").equipped)
	for frame: int in range(420):
		await physics_frame
		if boss.state == boss.State.CHASE:
			break
	assert(boss.state == boss.State.CHASE)
	assert(boss.tutorial_encounter.elite_horde_started)
	var mob: Minotaur = load("res://scenes/enemies/minotaur.tscn").instantiate() as Minotaur
	arena.add_child(mob)
	mob.global_position = boss.actor.global_position + Vector2(12, 0)
	var before: float = mob.resistance
	boss.impact_position = mob.global_position
	boss.damage_emitted = false
	boss.call(&"_impact")
	assert(is_equal_approx(mob.resistance, before - boss.preview_damage))
	boss.call(&"_impact")
	assert(is_equal_approx(mob.resistance, before - boss.preview_damage))
	print("TAB_SKIP_AND_FRIENDLY_FIRE_OK")
	quit()
