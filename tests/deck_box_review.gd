extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var arena: Node2D = main.get_node("TutorialArena") as Node2D
	var starting_gun: Node2D = arena.get_node("Mox/BoosterShooter") as Node2D
	await physics_frame
	assert(starting_gun.visible and starting_gun.equipped)
	assert((starting_gun.get_node("DeckBox") as Node2D).visible)
	await arena.entrance_finished
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://renders/deck_box_tutorial_start.png")
	var player: Player = arena.get_node("Mox") as Player
	var boss: Node2D = arena.get_node("MinotaurChair") as Node2D
	boss.set_physics_process(false)
	boss.set_process(false)
	var encounter: Node = boss.get("tutorial_encounter")
	encounter.set_process(false)
	player.position = Vector2(0, 80)
	player.intro_locked = false
	player.set_physics_process(false)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	var gun: Node2D = player.get_node("BoosterShooter") as Node2D
	assert(gun.visible and gun.equipped)
	assert((gun.get_node("DeckBox") as Node2D).visible)
	gun.call("set_combat_enabled", true)
	await create_timer(0.3).timeout
	var box: Node2D = gun.get_node("DeckBox") as Node2D
	assert(not (gun.get_node("WeaponPivot/Weapon") as Sprite2D).visible)
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var target: Vector2 = player.global_position + direction * 80.0
		root.warp_mouse(root.get_canvas_transform() * target)
		await create_timer(0.12).timeout
		gun.set("cooldown", 0.0)
		var bullet: Node2D = gun.call("fire_once") as Node2D
		assert(bullet != null)
		assert(bullet.global_position.distance_to(box.global_position) < 1.5)
		var actual_target: Vector2 = root.get_canvas_transform().affine_inverse() * root.get_mouse_position()
		assert((bullet.get("direction") as Vector2).dot((actual_target - bullet.global_position).normalized()) > 0.99)
		bullet.queue_free()
	player.velocity = Vector2(82, 0)
	await create_timer(0.5).timeout
	assert(float(box.get("shoulder")) == -1.0)
	player.velocity = Vector2(-82, 0)
	await create_timer(0.5).timeout
	assert(float(box.get("shoulder")) == 1.0)
	player.velocity = Vector2.ZERO
	var mob: Node2D = encounter.get_node("Horde").call("_spawn", player.global_position + Vector2(80, 0)) as Node2D
	mob.set_physics_process(false)
	root.warp_mouse(root.get_canvas_transform() * mob.global_position)
	await create_timer(0.15).timeout
	gun.set("cooldown", 0.0)
	var live_shot: Node2D = gun.call("fire_once") as Node2D
	mob.global_position = live_shot.global_position + (live_shot.get("direction") as Vector2) * 65.0
	await create_timer(0.6).timeout
	assert(float(mob.get("resistance")) < 18.0)
	player.intro_locked = true
	gun.set("cooldown", 0.0)
	assert(gun.call("fire_once") == null)
	player.intro_locked = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://renders/deck_box_combat.png")
	print("DECK BOX PASS: muzzle, aim in four directions, following sides, real damage, tutorial lock")
	quit()
