extends SceneTree
var failures: int = 0

func _initialize() -> void:
	call_deferred(&"run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	for index: int in range(1, 6):
		var texture: Texture2D = load("res://assets/enemies/minotaur/elite/defeated/defeated%d.png" % index)
		var pixels: Image = texture.get_image()
		print("DEFEATED ", index, " size=", pixels.get_size(), " used=", pixels.get_used_rect(), " background=", pixels.get_pixel(8, 28))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	if "--legacy" in OS.get_cmdline_user_args():
		main.get_node("TutorialArena/Mox/BoosterShooter").use_deck_box = false
	root.add_child(main)
	current_scene = main
	var arena: Node = main.get_node("TutorialArena")
	var boss: Node = arena.get_node("MinotaurChair")
	var player: Player = arena.get_node("Mox") as Player
	var encounter: Node = boss.tutorial_encounter
	var completion: Node = encounter.completion
	await arena.entrance_finished
	check(not arena.exit_available, "Exit must be locked before victory")
	player.receive_contact_damage(6)
	check(player.health == 54.0, "Contact must reduce Nox HP")
	player.receive_contact_damage(6)
	check(player.health == 54.0, "Contact immunity must prevent repeated damage")
	encounter.skip_to_boss()
	check(player.health == 60.0, "Boss entry heals Nox")
	var elite_lesson_seen: bool = false
	for frame: int in range(420):
		await physics_frame
		if completion.elite_modal.visible:
			elite_lesson_seen = true
			completion.elite_ok.emit_signal(&"pressed")
		if boss.state == boss.State.CHASE:
			break
	check(boss.state == boss.State.CHASE, "Boss must land and chase")
	for frame: int in range(45):
		await physics_frame
		if completion.elite_modal.visible:
			elite_lesson_seen = true
			completion.elite_ok.emit_signal(&"pressed")
			break
	check(elite_lesson_seen, "Elite lesson must appear after the landing delay")
	check(not paused, "Elite lesson must resume the encounter after OK")
	check(boss.actor.has_method("take_damage"), "Moving boss needs damage receiver")
	player.position = Vector2(0, 80)
	player.get_node("Camera2D").reset_smoothing()
	await capture("combat")
	var mob: Minotaur = encounter.horde._spawn(boss.actor.global_position + Vector2(120, 0))
	check(mob.resistance == 18, "Minion health uses balancing")
	# Verify wall collision and occlusion behind the throne.
	mob.set_physics_process(false)
	mob.global_position = boss.global_position + Vector2(0, 40)
	var collision: KinematicCollision2D = mob.move_and_collide(Vector2(0, -80))
	check(collision != null, "Throne must block minotaurs physically")
	mob.global_position = boss.global_position + Vector2(0, -50)
	mob._physics_process(0.0)
	check(mob.z_index < boss.z_index, "Minotaur behind throne must draw behind it")
	boss.set_physics_process(false)
	boss.body_shape.set_deferred("disabled", false)
	await physics_frame
	var live_bullet: Node2D = load("res://scenes/combat/projectiles/rapid_electric_bullet.tscn").instantiate()
	encounter.projectiles.add_child(live_bullet)
	live_bullet.global_position = boss.actor.global_position + Vector2(0, 50)
	live_bullet.setup(Vector2.UP, encounter.effects)
	for frame: int in range(25):
		await physics_frame
	check(boss.health == 264.0, "A real traveling projectile must hit the moving boss body")
	var death_point: Vector2 = boss.actor.global_position
	for shot_index: int in range(44):
		var bullet: Node2D = load("res://scenes/combat/projectiles/rapid_electric_bullet.tscn").instantiate()
		encounter.projectiles.add_child(bullet)
		bullet.setup(Vector2.UP, encounter.effects)
		bullet._on_body_entered(boss.actor)
	check(boss.health == 0.0 and boss.state == boss.State.DEFEATED, "45 combined shots must defeat Asterion")
	check(encounter.phase == encounter.Phase.VICTORY, "Defeat enters victory")
	check(not encounter.horde.active and encounter.horde.alive.is_empty(), "Victory clears and stops horde")
	check(not boss.start_skybreaker(), "Defeated boss cannot jump")
	boss.set_physics_process(true)
	for frame: int in range(65):
		await physics_frame
	check(boss.visual.texture == boss.DEFEATED_FRAMES[4], "Corpse must keep defeated5")
	check(boss.actor.global_position.is_equal_approx(death_point), "Corpse must stay where defeated")
	await capture("surrender")
	check(encounter.dialogue.is_dialogue_active(), "Surrender dialogue should start")
	for line_index: int in range(8):
		encounter.dialogue.reveal_current_line()
		encounter.dialogue.advance()
		await process_frame
	check(completion.rewards_granted, "Rewards must be granted after surrender")
	for frame: int in range(260):
		await physics_frame
	check(arena.exit_available, "Stair should return after surrender")
	check(arena.stair.position.is_equal_approx(arena.stair_home), "Stair must return to original position")
	await capture("victory")
	player.position = Vector2(arena.stair_home.x, player.movement_bounds.end.y - 4)
	for frame: int in range(100):
		await physics_frame
	check(completion.completed and encounter.phase == encounter.Phase.FINISHED, "Walking to stair ends tutorial")
	check(completion.end_screen.visible, "End screen must show")
	await capture("ending")
	print("TUTORIAL_COMPLETION failures=", failures)
	quit(1 if failures else 0)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/tutorial_" + label + ".png")
