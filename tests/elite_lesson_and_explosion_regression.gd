extends SceneTree

func _initialize() -> void:
	call_deferred(&"run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node = main.get_node("TutorialArena")
	var boss: Node = arena.get_node("MinotaurChair")
	var encounter: Node = boss.tutorial_encounter
	var completion: Node = encounter.completion
	await arena.entrance_finished
	encounter.skip_to_boss()
	assert(completion.boss_label.text == "ASTERION")
	assert(not completion.boss_label.text.contains("/"))
	completion._explain_elite(Vector2.ZERO)
	await create_timer(0.55).timeout
	assert(paused and completion.elite_modal.visible)
	completion.elite_ok.emit_signal(&"pressed")
	assert(not paused and not completion.elite_modal.visible)
	completion.show_controls_lesson()
	assert(paused and completion.elite_modal.visible)
	completion.elite_ok.emit_signal(&"pressed")
	assert(not paused and not completion.elite_modal.visible)
	var point: Vector2 = Vector2(0.0, 0.0)
	encounter.effects.trigger_explosion(point, 18.0, 3.0)
	encounter.effects.trigger_explosion(point, 18.0, 3.0)
	assert(encounter.effects.active_explosion_visuals.size() == 1)
	var burst: Node2D = encounter.effects.active_explosion_visuals[0]
	assert(is_instance_valid(burst) and burst.global_position.is_equal_approx(point))
	print("ELITE_LESSON_AND_EXPLOSION_OK")
	quit()
