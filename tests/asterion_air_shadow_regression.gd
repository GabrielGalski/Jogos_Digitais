extends SceneTree


func _initialize() -> void:
	call_deferred(&"run")


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node2D = main.get_node("TutorialArena") as Node2D
	var boss: Node = arena.get_node("MinotaurChair")
	var player: CharacterBody2D = arena.get_node("Mox") as CharacterBody2D
	await arena.entrance_finished
	player.global_position = arena.to_global(Vector2(0.0, 40.0))
	player.reset_physics_interpolation()
	boss.call(&"_enter_chase")
	assert(boss.call(&"start_skybreaker"))
	for frame: int in range(90):
		await physics_frame
		if boss.state == boss.State.OFFSCREEN:
			break
	assert(boss.state == boss.State.OFFSCREEN)
	assert(boss.shadow.visible)
	assert(boss.shadow.get_parent() == boss)
	var first_prediction: Vector2 = boss.shadow.global_position
	player.global_position += Vector2(64.0, 0.0)
	for frame: int in range(20):
		await physics_frame
	var prediction_distance: float = boss.shadow.global_position.distance_to(first_prediction)
	assert(prediction_distance > 16.0, "prediction distance=%s first=%s current=%s player=%s locked=%s time=%s" % [prediction_distance, first_prediction, boss.shadow.global_position, player.global_position, boss.target_is_locked, boss.state_time])
	var initial_scale: Vector2 = boss.shadow.scale
	for frame: int in range(45):
		await physics_frame
	assert(boss.shadow.scale.x > initial_scale.x)
	for frame: int in range(360):
		await physics_frame
		if boss.state == boss.State.HIT_1:
			break
	assert(boss.state == boss.State.HIT_1)
	assert(not boss.shadow.visible)
	for frame: int in range(120):
		await physics_frame
		if boss.state == boss.State.CHASE:
			break
	assert(boss.state == boss.State.CHASE)
	assert(boss.shadow.get_parent() == boss.actor and boss.shadow.visible)
	assert(boss.shake_pixels == 12.0)
	print("ASTERION_AIR_SHADOW_OK")
	quit()
