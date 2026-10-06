extends SceneTree

var dungeon: Node2D
var player: Player

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("DUNGEON FAIL: " + message)
		quit(1)
		assert(condition, message)

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _capture(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://renders/" + file + ".png")

func _move_to(point: Vector2) -> void:
	player.position = point
	player.reset_physics_interpolation()
	(player.get_node("Camera2D") as Camera2D).reset_smoothing()
	await physics_frame
	await physics_frame

func _clear_encounter(encounter: Node2D) -> void:
	var deadline: int = Time.get_ticks_msec() + 16000
	while int(encounter.get("phase")) != 5 and Time.get_ticks_msec() < deadline:
		for enemy: Node in get_nodes_in_group("minotaurs"):
			(enemy as Minotaur).take_damage(999.0)
		await create_timer(0.12).timeout
	_check(int(encounter.get("phase")) == 5, "encounter must complete")

func _run() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/merchant_corridor.tscn", "starts at merchant")
	change_scene_to_file("res://scenes/merchant_corridor.tscn")
	await create_timer(2.2).timeout
	var merchant: Node2D = current_scene as Node2D
	_check(int(merchant.get("state")) == 2, "merchant entrance finished")
	merchant.set("ground_position", Vector2(952, 28))
	await create_timer(1.4).timeout
	dungeon = current_scene as Node2D
	_check(dungeon.name == "DungeonPreview", "merchant exit changes scene")
	player = dungeon.get_node("Nox") as Player
	_check(not player.intro_locked, "arrival enables movement")
	var gun: Node2D = player.get_node("BoosterShooter") as Node2D
	_check(bool(gun.get("combat_enabled")) and gun.visible, "caster enabled from start")
	_check(player.position.x < 0.0, "starts in entrance corridor")
	await _capture("dungeon_entrance")
	_key(KEY_D, true)
	await create_timer(1.55).timeout
	_key(KEY_D, false)
	_check(int(dungeon.get("stage")) == 2, "walking triggers first room")
	_check((dungeon.get_node("Layout/Room1/EntranceGate") as StaticBody2D).collision_layer == 17, "entrance closes behind Nox")
	_check((dungeon.get_node("Layout/Room1/PassageGate") as StaticBody2D).collision_layer == 17, "next passage stays closed")
	await _move_to(Vector2(300, 96))
	_check(player.test_move(player.global_transform, Vector2(40, 0)), "locked gate blocks walking/dash")
	await _move_to(Vector2(32, 16))
	_check(not player.test_move(player.global_transform, Vector2(0, -48)), "room edge has no wall collision")
	await _move_to(Vector2(80, 96))
	await create_timer(1.0).timeout
	var first: Minotaur = get_first_node_in_group("minotaurs") as Minotaur
	_check(first != null, "minotaurs spawn")
	var before: Vector2 = first.global_position
	await create_timer(0.35).timeout
	_check(first.global_position.distance_to(before) > 1.0, "AI actively pursues")
	first.set_physics_process(false)
	first.position = Vector2(160, 96)
	root.warp_mouse(root.get_canvas_transform() * first.global_position)
	await create_timer(0.2).timeout
	gun.set("cooldown", 0.0)
	var bullet: RapidElectricBullet = gun.call("fire_once") as RapidElectricBullet
	_check(bullet != null, "live weapon fires")
	first.position = bullet.global_position + bullet.direction * 45.0
	await create_timer(0.4).timeout
	_check(first.resistance < first.max_resistance, "real projectile damages minotaur")
	first.set_physics_process(true)
	# The locked passage remains a projectile obstacle even without walls.
	var gate_shot: RapidElectricBullet = load("res://scenes/combat/projectiles/rapid_electric_bullet.tscn").instantiate() as RapidElectricBullet
	dungeon.get_node("Projectiles").add_child(gate_shot)
	gate_shot.position = Vector2(300, 96)
	gate_shot.obstacle_mask = 16
	gate_shot.setup(Vector2.RIGHT, dungeon.get_node("Effects") as CombatEffects)
	await create_timer(0.12).timeout
	_check(not is_instance_valid(gate_shot), "projectile stops at locked passage")
	await _capture("dungeon_room_one")
	# Progression coverage uses lethal damage, not a claim of manual combat balancing.
	player.contact_invulnerability = 60.0
	await _clear_encounter(dungeon.get_node("Room1Encounter") as Node2D)
	await physics_frame
	_check(int(dungeon.get_node("Room1Encounter").get("spawned")) == 6, "exactly six spawned")
	_check(int(dungeon.get("stage")) == 3, "first clear unlocks corridor")
	await _move_to(Vector2(360, 96))
	await create_timer(0.3).timeout
	var caster: Node2D = gun.get_node("DeckBox") as Node2D
	var caster_start: Vector2 = caster.global_position
	var nox_start: Vector2 = player.position
	_check(player.try_dash(Vector2.RIGHT), "dash starts in narrow corridor")
	await create_timer(0.1).timeout
	_check(player.position.x - nox_start.x > caster.global_position.x - caster_start.x, "caster lags independently during dash")
	await create_timer(0.15).timeout
	_check(player.position.x > 405.0, "dash advances along the open corridor")
	_check(absf(player.position.y - 96.0) < 1.0, "dash keeps its horizontal direction")
	player.try_dash(Vector2.RIGHT)
	await create_timer(0.4).timeout
	await _move_to(Vector2(300, 96))
	_key(KEY_D, true)
	await create_timer(1.4).timeout
	_key(KEY_D, false)
	_check(player.position.x > 405.0, "walk through unlocked passage")
	await _move_to(Vector2(416, 96))
	_key(KEY_W, true)
	await create_timer(1.75).timeout
	_key(KEY_W, false)
	_check(float(dungeon.get("reveal")) > 0.0 and float(dungeon.get("reveal")) < 1.0, "room reveal starts on approach")
	await _capture("dungeon_corridor_reveal")
	_key(KEY_W, true)
	await create_timer(1.0).timeout
	_key(KEY_W, false)
	_check(int(dungeon.get("stage")) == 4, "corridor enters second room continuously")
	_check(current_scene == dungeon, "no scene reload between rooms")
	_check((dungeon.get_node("Layout/Room2/EntranceGate") as StaticBody2D).collision_layer == 17, "second entry locks")
	await _move_to(Vector2(540, -250))
	await create_timer(1.2).timeout
	await _capture("dungeon_room_two")
	await _clear_encounter(dungeon.get_node("Room2Encounter") as Node2D)
	await physics_frame
	_check(int(dungeon.get_node("Room2Encounter").get("spawned")) == 8, "second room two waves of four")
	_check(int(dungeon.get("stage")) == 5, "elite placeholder completes")
	_check((dungeon.get_node("Layout/Room2/ExitDownGate") as StaticBody2D).collision_layer == 0, "down exit unlocked")
	_check((dungeon.get_node("Layout/Room2/ExitRightGate") as StaticBody2D).collision_layer == 0, "right exit unlocked")
	await _move_to(Vector2(672, -112))
	_key(KEY_S, true)
	await create_timer(1.3).timeout
	_key(KEY_S, false)
	_check(int(dungeon.get("chosen_exit")) == 1, "down exit ends gameplay")
	await create_timer(0.7).timeout
	await _capture("dungeon_complete")
	_key(KEY_R, true)
	_key(KEY_R, false)
	await create_timer(0.7).timeout
	_check(current_scene.name == "MerchantCorridor", "R returns to merchant")
	# Independently exercise the right exit and death return in fresh instances.
	change_scene_to_file("res://scenes/dungeon/dungeon_preview.tscn")
	await create_timer(0.6).timeout
	dungeon = current_scene as Node2D
	player = dungeon.get_node("Nox") as Player
	dungeon.set("stage", 4)
	dungeon.call("_room_two_cleared")
	await _move_to(Vector2(752, -272))
	_key(KEY_D, true)
	await create_timer(1.6).timeout
	_key(KEY_D, false)
	_check(int(dungeon.get("chosen_exit")) == 2, "right exit ends gameplay")
	change_scene_to_file("res://scenes/dungeon/dungeon_preview.tscn")
	await create_timer(0.6).timeout
	dungeon = current_scene as Node2D
	player = dungeon.get_node("Nox") as Player
	player.receive_skybreaker_hit(999.0)
	await create_timer(0.7).timeout
	_check(current_scene.name == "MerchantCorridor", "death returns to safe room")
	print("DUNGEON PASS: merchant transition, open rooms/corridors, sealed gates, 6+8 enemies, AI, live damage, gate shots, reveal, no reload, both exits, restart and death")
	quit()
