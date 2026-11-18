extends SceneTree
const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const ENEMY: Script = preload("res://scripts/enemies/open_world_horde_enemy.gd")
const ENEMIES: Script = preload("res://scripts/enemies/open_world_horde_catalog.gd")
const EFFECTS: Script = preload("res://scripts/cards/card_effect_controller.gd")
const FACTORY: Script = preload("res://scripts/combat/manifestations/manifestation_factory.gd")
const SNAKE: Script = preload("res://scripts/cards/medusa_snake.gd")
var failures: Array[String] = []
var checks: int = 0
var world: Node2D
var player: Player
var gun: Node2D
var controller: Node
var service: EFFECTS
var fixtures: Array[Node2D] = []
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func runtime() -> CardCombatRuntime:
	return gun.get("card_runtime") as CardCombatRuntime


func target(offset: Vector2, health: float = 100.0) -> ENEMY:
	var enemy: ENEMY = ENEMY.new()
	enemy.configure("goblin", player, Callable(world, "_terrain_and_warp_height"))
	enemy.position = player.global_position + offset
	enemy.resistance = health
	world.add_child(enemy)
	fixtures.append(enemy)
	return enemy


func clear() -> void:
	for enemy: Node2D in fixtures:
		if is_instance_valid(enemy):
			enemy.queue_free()
	fixtures.clear()
	service.poisons.clear()
	service.blasts.clear()
	service.mouths.clear()
	service.clouds.clear()
	for child: Node in service.get_children():
		if child is Node2D:
			child.queue_free()
	await ticks(2)


func equip(infusion: int, mutation: int) -> void:
	controller.call("select_infusion", infusion)
	controller.call("select_mutation", mutation)
	service._bind_runtime()
	runtime().cooldowns.clear()


func key(code: Key) -> void:
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = code
	press.keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventKey = press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)


func capture(name: String) -> void:
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/card_effects/" + name + ".png")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/card_effects")
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	world = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	world.set("warp_entry_cutscene_enabled", false)
	world.set("insect_spawns_enabled", false)
	root.add_child(world)
	current_scene = world
	for name: String in ["FlyingSkullZones", "SlimeZones"]:
		world.get_node(name).set_physics_process(false)
	while not bool(world.get("entry_complete")):
		await process_frame
	player = world.get_node("Nox") as Player
	player.set_physics_process(false)
	player.global_position = Vector2(1600, 880)
	player.snap_floor_height()
	service = player.get_node("GameplayKit/CardEffects") as EFFECTS
	gun = player.get_node("BoosterShooter") as Node2D
	controller = player.get_node("GameplayKit/Manifestations")
	controller.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	await ticks(3)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	# Actual selectors, five infusions and six mutations.
	controller.call("open_equipment_menu")
	await ticks(2)
	var menu: Node = controller.get("_equipment_menu") as Node
	menu.call("show_aspect", 1)
	check((menu.get("cards") as Array).size() == 5, "Five infusion cards are selectable")
	((menu.get("model_buttons") as Dictionary)[2] as Button).pressed.emit()
	check(runtime().copy_loadout().infusion.effect == 2, "GUI selects Odopi")
	menu.call("show_aspect", 2)
	check((menu.get("cards") as Array).size() == 6, "Six mutation cards are selectable")
	((menu.get("model_buttons") as Dictionary)[5] as Button).pressed.emit()
	check(runtime().mutation_effect() == 5, "GUI selects Doppelganger")
	check((menu.get("_title") as Label).text == "Mutação", "Picker title follows the selected aspect")
	await ticks(20)
	await capture("01-mutation-picker")
	menu.queue_free()
	await ticks(3)
	# I01: independent explosions of 18, 9, 3, 3 damage and fixed radius.
	equip(0, 0)
	var first_victim: ENEMY = target(Vector2(40, 0), 3.0)
	var second: ENEMY = target(Vector2(52, 0), 18.0)
	var third: ENEMY = target(Vector2(64, 0), 9.0)
	var fourth: ENEMY = target(Vector2(76, 0), 3.0)
	var survivor: ENEMY = target(Vector2(88, 0))
	var attack: CardAttack = runtime().create_attack()
	attack.apply_primary_hit(first_victim, first_victim.get_visual_center_of_mass(), Vector2.RIGHT, service.effects())
	service._drain_blasts()
	check(not second.is_alive() and not third.is_alive() and not fourth.is_alive(), "Cascade resolves successive kills")
	check(is_equal_approx(survivor.resistance, 97.0) and service.blasts.is_empty(), "Cascade reaches the three-damage floor and ends without another kill")
	check(runtime().mutation_remaining > 0.0, "Cascade kills refresh Fury")
	await clear()
	# I02: six swept rocks carry fifteen percent of the killing hit.
	equip(1, -1)
	first_victim = target(Vector2(20, 0), 20.0)
	attack = runtime().create_attack()
	attack.damage = 20.0
	attack.apply_primary_hit(first_victim, first_victim.get_visual_center_of_mass(), Vector2.RIGHT, service.effects())
	var shards: Array[Node] = get_nodes_in_group(&"card_fragments")
	check(shards.size() == 6, "A kill creates six stones")
	check(is_equal_approx(float(shards[0].get("damage")), 3.0), "Stone damage is fifteen percent of final damage")
	await clear()
	# I03 and U01 respond to one credited death.
	equip(2, 0)
	player.health = 30.0
	first_victim = target(Vector2(40, 0), 3.0)
	attack = runtime().create_attack()
	attack.apply_primary_hit(first_victim, first_victim.get_visual_center_of_mass(), Vector2.RIGHT, service.effects())
	attack.apply_primary_hit(first_victim, first_victim.get_visual_center_of_mass(), Vector2.RIGHT, service.effects())
	check(is_equal_approx(player.health, 31.8) and runtime().movement_multiplier() > 1.0, "One kill heals three percent and grants Fury once")
	await clear()
	# I04 payload, real host attachment, friendly shot, cooldown and boss exclusion.
	equip(3, -1)
	attack = runtime().create_attack()
	check(attack.slaad_carrier and not runtime().create_attack().slaad_carrier, "Slaad payload obeys its six-second clock")
	first_victim = target(Vector2(40, 0))
	second = target(Vector2(105, 0))
	attack.apply_primary_hit(first_victim, first_victim.get_visual_center_of_mass(), Vector2.RIGHT, service.effects())
	check(first_victim.is_in_group(&"controlled_monsters") and first_victim.has_meta(&"card_control"), "Slaad attaches to and controls a normal enemy")
	var control: Node = first_victim.get_meta(&"card_control") as Node
	control.call("_physics_process", 0.1)
	var friendly: Array[Node] = get_nodes_in_group(&"card_fragments")
	check(not friendly.is_empty(), "Controlled enemy attacks another monster")
	if not friendly.is_empty():
		(friendly.back() as Node).call("_physics_process", 0.5)
	check(second.resistance < 100.0, "Controlled enemy projectiles damage monsters")
	await ticks(2)
	await capture("06-slaad")
	third = target(Vector2(90, 40))
	third.set_meta(&"is_boss", true)
	service.attach_slaad(third)
	check(not third.has_meta(&"card_control"), "Boss-capable actors reject Slaad")
	control.queue_free()
	await ticks(2)
	check(not first_victim.has_meta(&"card_control") and not first_victim.is_in_group(&"controlled_monsters"), "Host restores original control on expiration")
	await clear()
	# I05: each snapshot preserves its own phase.
	equip(4, -1)
	first_victim = target(Vector2(45, 0))
	for element: int in range(3):
		attack = runtime().create_attack()
		check(attack.element == element, "Chimera cycles fire, poison, push")
		attack.apply_primary_hit(first_victim, first_victim.get_visual_center_of_mass(), Vector2.RIGHT, service.effects())
	check(not service.poisons.is_empty() and first_victim.hit_velocity.length() > 0.0, "Chimera applies poison and push")
	var model: ProceduralManifestationModel = controller.call("selected_model") as ProceduralManifestationModel
	var shot: Node2D = FACTORY.projectile(model, attack, world, player.surface_world_position(), Vector2.RIGHT, service.effects(), player, controller.get("sprites") as ProceduralWeaponSpriteFactory)
	check(shot.get_node("ProceduralVisual/Core32").material is ShaderMaterial, "Chimera modifies the projectile outline")
	shot.queue_free()
	await clear()
	# U02: actual enemy damage, one snake per 1.5s, authored attack/defeat.
	equip(-1, -1)
	player.health = 60.0
	player.contact_invulnerability = 0.0
	var expired_shooter: ENEMY = target(Vector2(45, 0))
	var orb := preload("res://scripts/combat/projectiles/flying_eye_orb.gd").new()
	orb.target = player
	orb.shooter = expired_shooter
	orb.position = player.global_position + (player.get_node("CollisionShape2D") as CollisionShape2D).position
	world.add_child(orb)
	service.poison(expired_shooter, 2.0, 1.0)
	expired_shooter.free()
	await ticks(2)
	check(player.health < 60.0 and player.last_damage_source == null, "A projectile still hits after its shooter is freed")
	check(service.poisons.is_empty(), "Poison releases an expired target")
	equip(-1, 1)
	player.health = 60.0
	first_victim = target(Vector2(14, 0))
	player.contact_invulnerability = 0.0
	player.receive_projectile_damage(3, first_victim)
	var snakes: Array[Node] = get_nodes_in_group(&"medusa_snakes")
	check(snakes.size() == 1 and (snakes[0] as Node2D).global_position.distance_to(player.global_position) < 1.0, "Enemy damage spawns one snake at the player")
	player.contact_invulnerability = 0.0
	player.receive_projectile_damage(3, first_victim)
	check(get_nodes_in_group(&"medusa_snakes").size() == 1, "Rapid damage respects Medusa cooldown")
	var snake: SNAKE = snakes[0] as SNAKE
	check(snake.visual.sprite_frames.get_frame_count(&"walk") == 8 and snake.visual.sprite_frames.get_frame_count(&"attack") == 6 and snake.visual.sprite_frames.get_frame_count(&"defeat") == 6, "Snake rows are mapped to their authored states")
	await ticks(2)
	await capture("07-medusa-snake")
	player.contact_invulnerability = 1000.0
	var final_bites: Array[int] = []
	snake.tree_exiting.connect(func() -> void: final_bites.append(snake.bites))
	await ticks(180)
	check(not final_bites.is_empty() and final_bites[0] == 3, "Snake plays defeat after its third attack")
	await clear()
	var idle_snake: SNAKE = SNAKE.new()
	idle_snake.service = service
	service.add_child(idle_snake)
	idle_snake.age = 5.98
	await ticks(3)
	check(idle_snake.dying and idle_snake.bites == 0, "Six seconds also ends a snake without bites")
	await clear()
	# U03: harmless warning first, delayed area damage.
	equip(-1, 2)
	first_victim = target(Vector2(30, 0))
	service._physics_process(0.01)
	check(first_victim.resistance == 100.0 and service.mouths.size() == 1, "Carnivorous circle warns before damaging")
	service._tick_mouths(0.24)
	check(first_victim.resistance == 100.0, "Warning lasts at least 0.25 seconds")
	service._tick_mouths(0.02)
	check(first_victim.resistance == 94.0, "Mouth deals area damage after its warning")
	await capture("02-carnivorous")
	await clear()
	# U04: real F input triggers popup and displacement.
	equip(-1, 3)
	first_victim = target(Vector2(40, 0))
	key(KEY_E)
	await ticks(1)
	check(float(runtime().cooldowns.get(&"U04", 0.0)) == 0.0, "E does not activate the mutation")
	key(KEY_F)
	await ticks(2)
	check(first_victim.hit_velocity.length() > 0.0 and float(runtime().cooldowns.get(&"U04", 0.0)) > 0.0, "F triggers Mandrake displacement and cooldown")
	check(first_victim.global_position.distance_to(player.global_position) > 50.0, "Pulse physically separates the monster from Nox")
	check((service.get("_status") as Label).text.begins_with("F  "), "Mutation hint displays the F action key")
	await capture("03-mandrake")
	await clear()
	# U05: movement creates a finite poison trail, idle does not.
	equip(-1, 4)
	for index: int in range(4):
		player.position.x += 13.0
		await ticks(1)
	check(not service.clouds.is_empty(), "Movement leaves poison smoke")
	var cloud_count: int = service.clouds.size()
	await ticks(10)
	check(service.clouds.size() == cloud_count, "Idle does not emit more trail")
	first_victim = target(Vector2.ZERO)
	await ticks(60)
	check(first_victim.resistance < 100.0, "Poison smoke damages overlapping enemies")
	await capture("04-poison-trail")
	await clear()
	# U06: manual disappearance, shooting suppression, and a saved lethal hit.
	equip(-1, 5)
	player.health = 60.0
	first_victim = target(Vector2(50, 0))
	player.set_physics_process(true)
	player.body.facing = Vector2.LEFT
	var departure: Vector2 = player.global_position
	key(KEY_F)
	await ticks(2)
	check(player.mutation_invisible and player.body.visible and is_equal_approx(player.body.self_modulate.a, 0.35) and is_instance_valid(service.decoy), "F leaves a visible copy and makes the player translucent")
	check(gun.call("fire_once") == null, "Invisible player cannot shoot")
	check(not service.activate_mutation() and float(runtime().cooldowns.get(&"U06", 0.0)) > 29.0, "Manual use starts the shared thirty-second cooldown")
	await ticks(15)
	check(absf(player.global_position.distance_to(departure) - player.dash_speed * player.dash_duration) < 2.0 and service.decoy.global_position.is_equal_approx(departure), "Decoy stays behind a full dash")
	await capture("05-doppelganger")
	await ticks(95)
	check(not player.mutation_invisible and player.body.visible and is_equal_approx(player.body.self_modulate.a, 1.0), "Player returns after 1.5 seconds")
	runtime().cooldowns[&"U06"] = 0.0
	player.health = 1.0
	player.contact_invulnerability = 0.0
	player.receive_projectile_damage(3, first_victim)
	check(not player.dead and is_equal_approx(player.health, 6.0) and player.mutation_invisible, "Ready Doppelganger prevents death and restores ten percent health")
	await clear()
	# All six existing manifestations support each of the thirty I/U selections.
	service.invisible_remaining = 0.0
	player.mutation_invisible = false
	player.health = 60.0
	for manifest: int in range(6):
		controller.call("select_model", manifest)
		for infusion: int in range(5):
			for mutation: int in range(6):
				equip(infusion, mutation)
				attack = runtime().create_attack()
				check(attack != null and attack.infusion_effect == infusion and runtime().mutation_effect() == mutation, "Selected trio has its own valid combat snapshot")
	# Lethal damage during recharge must still reach the actual defeat flow.
	equip(-1, 5)
	runtime().cooldowns[&"U06"] = 20.0
	player.health = 1.0
	player._apply_health_damage(3.0)
	check(player.dead, "Doppelganger cannot prevent another death while recharging")
	world.queue_free()
	await ticks(3)
	var report: FileAccess = FileAccess.open("res://output/card_effects/regression.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("CARD_EFFECTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
