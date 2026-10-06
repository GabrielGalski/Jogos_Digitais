extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var arena: Node2D = main.get_node("TutorialArena") as Node2D
	var player: Player = arena.get_node("Mox") as Player
	assert(not player.try_dash(Vector2.RIGHT), "Dash must be blocked during entrance")
	await arena.entrance_finished
	var boss: Node2D = arena.get_node("MinotaurChair") as Node2D
	boss.set_physics_process(false)
	boss.set_process(false)
	(boss.get("tutorial_encounter") as Node).set_process(false)
	player.position = Vector2(0, 80)
	player.intro_locked = false
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	var caster: Node2D = player.get_node("BoosterShooter/DeckBox") as Node2D
	await create_timer(0.5).timeout
	var start: Vector2 = player.global_position
	var caster_start: Vector2 = caster.global_position
	var base_camera: Vector2 = camera.position
	Input.action_press(&"dash")
	await physics_frame
	await physics_frame
	Input.action_release(&"dash")
	assert(player.is_dashing(), "Space action must start dash")
	assert(not player.try_dash(Vector2.RIGHT), "No second dash during cooldown")
	for frame: int in range(4):
		await physics_frame
	assert(get_nodes_in_group(&"dash_afterimages").size() >= 2, "Dash must leave afterimages")
	assert(camera.position.distance_to(base_camera) > 0.1, "Dash should affect camera")
	assert(caster.z_index < player.z_index + player.body.z_index, "Caster must stay behind Nox")
	assert(caster.global_position.distance_to(caster_start) < player.global_position.distance_to(start) * 0.8, "Caster must lag rather than move rigidly with dash")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://renders/nox_dash_mid.png")
	await create_timer(0.3).timeout
	assert(not player.is_dashing())
	assert(player.global_position.distance_to(start) > 45.0 and player.global_position.distance_to(start) < 56.0, "Dash range must be bounded")
	assert(get_nodes_in_group(&"dash_afterimages").is_empty(), "Trails must clean themselves up")
	assert(camera.position.distance_to(base_camera) < 0.05, "Camera must return without drift")
	await create_timer(0.4).timeout
	assert(caster.global_position.distance_to(player.global_position) < 23.0, "Caster should catch up smoothly")
	player.position = Vector2(328.0, 80.0)
	await physics_frame
	assert(player.try_dash(Vector2.RIGHT))
	await create_timer(0.2).timeout
	assert(player.position.x <= player.movement_bounds.end.x and not player.is_dashing(), "Dash must stop at walls")
	print("DASH PASS: input, lock, cooldown, range, trail, camera recovery, follower lag and catch-up, walls")
	quit()
