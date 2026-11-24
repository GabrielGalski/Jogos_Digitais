extends SceneTree
const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const ENEMY: Script = preload("res://scripts/enemies/open_world_horde_enemy.gd")
const ENEMIES: Script = preload("res://scripts/enemies/open_world_horde_catalog.gd")
const EFFECTS: Script = preload("res://scripts/cards/card_effect_controller.gd")
const FACTORY: Script = preload("res://scripts/combat/manifestations/manifestation_factory.gd")
const SNAKE: Script = preload("res://scripts/cards/medusa_snake.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
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
	for child: Node in service.get_children():
		if child.name == "Calimshan":
			child.call("_clear")
		elif child.name in ["VampireEffects", "DragonEffects"]:
			continue
		elif child is Node2D:
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
	check(runtime().copy_loadout().mutation.card_id == &"CARD_MUT_003", "Nox starts with Carnivorous Ground equipped")
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	# Actual selectors, five infusions and six mutations.
	controller.call("open_equipment_menu")
	await ticks(2)
	var menu: Node = controller.get("_equipment_menu") as Node
	menu.call("show_aspect", 1)
	check((menu.get("cards") as Array).size() == CATALOG.INFUSIONS.size(), "The full infusion catalog is selectable")
	((menu.get("model_buttons") as Dictionary)[2] as Button).pressed.emit()
	check(runtime().copy_loadout().infusion.effect == 2, "GUI selects Odopi")
	menu.call("show_aspect", 2)
	check((menu.get("cards") as Array).size() == CATALOG.MUTATIONS.size(), "The full mutation catalog is selectable")
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
	for victim: ENEMY in [first_victim, second, third, fourth, survivor]:
		victim.set_physics_process(false)
	var attack: CardAttack = runtime().create_attack()
	attack.apply_primary_hit(first_victim, first_victim.get_visual_center_of_mass(), Vector2.RIGHT, service.effects())
	check(second.is_alive() and service.blasts.size() == 1, "A weapon kill starts one explosion before its impact frame")
	await ticks(9)
	await capture("07-golem-cascade")
	await ticks(10)
	var second_defeated: bool = not is_instance_valid(second) or not second.is_alive()
	var third_defeated: bool = not is_instance_valid(third) or not third.is_alive()
	var fourth_defeated: bool = not is_instance_valid(fourth) or not fourth.is_alive()
	check(second_defeated and third_defeated and fourth_defeated, "Cascade resolves successive kills")
	check(is_equal_approx(survivor.resistance, 97.0) and service.blasts.is_empty(), "Cascade reaches the three-damage floor and ends without another kill")
	check(runtime().mutation_remaining > 0.0, "Cascade kills refresh Fury")
	await clear()
	first_victim = target(Vector2(32, 0), 1.0)
	second = target(Vector2(45, 0), 12.0)
	second.set_physics_process(false)
	service.mutation_hit(first_victim, 1.0)
	await ticks(5)
	check(not is_instance_valid(second) or not second.is_alive(), "An owned mutation kill also starts the golem cascade")
	await clear()
	first_victim = target(Vector2(32, 0), 1.0)
	player.apply_reflected_damage(first_victim, 1.0, Vector2.RIGHT)
	check(service.blasts.size() == 1, "Reflected player damage starts the golem cascade")
	await clear()
	first_victim = target(Vector2(32, 0), 1.0)
	first_victim.take_damage(1.0)
	check(service.blasts.is_empty(), "A death without player credit does not start an explosion")
	await clear()
	# I02: six light arrows carry fifteen percent of the killing hit.
	equip(1, -1)
	first_victim = target(Vector2(20, 0), 20.0)
	attack = runtime().create_attack()
	attack.damage = 20.0
	var contact: Vector2 = first_victim.get_visual_center_of_mass() - Vector2(4.0, 2.0)
	attack.apply_primary_hit(first_victim, contact, Vector2.RIGHT, service.effects())
	var shards: Array[Node] = get_nodes_in_group(&"card_fragments")
	var directions: Dictionary = {}
	for shard: Node2D in shards:
		directions[shard.get("direction")] = true
		check(shard.global_position.is_equal_approx(contact), "Light arrows depart from the killing projectile contact")
		check(is_equal_approx(float(shard.get("damage")), 3.0), "Arrow damage is fifteen percent of final damage")
	check(shards.size() == 6 and directions.size() == 6, "A kill creates six light arrows in distinct directions")
	await ticks(7)
	await capture("08-shard-arrows")
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
	check(attack.slaad_carrier and is_equal_approx(runtime().cooldowns[&"I04"], 3.0) and not runtime().create_attack().slaad_carrier, "Slaad payload obeys its three-second clock")
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
	runtime().tick(3.0)
	attack = runtime().create_attack()
	third = target(Vector2(90, 40))
	third.set_meta(&"is_boss", true)
	attack.apply_primary_hit(third, CONTACTS.damage_center(third), Vector2.RIGHT, service.effects())
	check(not third.has_meta(&"card_control") and attack.slaad_available(), "Bosses reject Slaad without spending the carried payload")
	var another_host: ENEMY = target(Vector2(32, 44))
	attack.apply_primary_hit(another_host, CONTACTS.damage_center(another_host), Vector2.RIGHT, service.effects())
	check(first_victim.is_in_group(&"controlled_monsters") and another_host.is_in_group(&"controlled_monsters"), "A second Slaad does not release the first host")
	check(is_equal_approx(float(control.get("duration")), 12.0), "Slaad control lasts twelve seconds")
	var health_before: float = first_victim.resistance
	attack.apply_primary_hit(first_victim, CONTACTS.damage_center(first_victim), Vector2.RIGHT, service.effects())
	check(is_equal_approx(first_victim.resistance, health_before), "Player projectiles do not wound controlled hosts")
	control.set("elapsed", 11.96)
	await ticks(1)
	check(first_victim.is_alive(), "The first host survives until its own timer ends")
	await ticks(5)
	check(not is_instance_valid(first_victim) or not first_victim.is_alive(), "The host dies at the end of possession")
	check(another_host.is_alive() and another_host.is_in_group(&"controlled_monsters"), "The other host keeps its own possession timer")
	await clear()
	# An actual Efreeti volley can infect with a side pellet.
	controller.call("select_model", 4)
	equip(3, -1)
	gun.set("aim_screen_override", root.get_canvas_transform() * (player.surface_world_position() + Vector2(220, 0)))
	gun.set("shot_recoil", 0.0)
	gun.call("_update_rig", 0.0)
	var muzzle: Vector2 = (gun.get_node("WeaponPivot/Muzzle") as Marker2D).global_position
	var aim: Vector2 = gun.get("aim_direction") as Vector2
	var side_contact: Vector2 = muzzle + aim * 3.0 + aim.orthogonal() * 3.6 + aim.rotated(deg_to_rad(18.0)) * 65.0
	var side_victim: ENEMY = target(side_contact - player.global_position)
	side_victim.global_position += side_contact - CONTACTS.damage_center(side_victim)
	side_victim.set_physics_process(false)
	var middle_pellet: Node2D = gun.call("fire_once") as Node2D
	check(middle_pellet != null, "Efreeti fires the charged volley")
	await ticks(15)
	check(side_victim.is_in_group(&"controlled_monsters"), "An off-axis Efreeti pellet delivers Slaad")
	await capture("10-efreeti-slaad")
	controller.call("cancel_attacks")
	controller.call("select_model", 0)
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
	first_victim.reset_physics_interpolation()
	await ticks(1)
	check(first_victim.resistance == 100.0 and service.mouths.size() == 1, "Carnivorous circle warns before damaging")
	check(EFFECTS.VISUAL.BITE_FRAMES.get_frame_count(&"bite") == 15 and EFFECTS.VISUAL.BITE_FRAMES.get_frame_texture(&"bite", 5).get_size() == Vector2(62, 72), "The authored bite has fifteen resized frames")
	await ticks(13)
	check(first_victim.resistance == 100.0, "Warning lasts at least 0.25 seconds")
	for index: int in range(4):
		if first_victim.resistance < 100.0:
			break
		await ticks(1)
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
	# U05: all three attacks resolve while the player is stationary.
	player.body.facing = Vector2.RIGHT
	equip(-1, 4)
	await ticks(2)
	check(runtime().copy_loadout().mutation.rarity == CardDefinition.Rarity.LEGENDARY, "Hero Sword is a legendary mutation")
	check(service.has_node("HeroSword") and service.get_node("HeroSword").get("_move") == &"idle", "Hero Sword floats beside an idle player")
	var idle_sword: Node2D = service.get_node("HeroSword") as Node2D
	check(idle_sword.global_position.distance_to(player.surface_world_position()) >= 30.0, "Idle sword leaves room beside Nox")
	first_victim = target(Vector2(22, 0))
	first_victim.set_physics_process(false)
	var outside: ENEMY = target(Vector2(136, 0))
	outside.set_physics_process(false)
	await ticks(29)
	check(is_equal_approx(first_victim.resistance, 96.0) and is_equal_approx(outside.resistance, 100.0), "Short cut hits exactly once without reaching outside the circle")
	await capture("04-hero-sword")
	equip(-1, -1)
	await ticks(2)
	check(not service.has_node("HeroSword"), "Unequipping removes the sword and cancels its attacks")
	await clear()
	equip(-1, 4)
	first_victim = target(Vector2(90, 0))
	first_victim.set_physics_process(false)
	var stationary: Vector2 = player.global_position
	await ticks(31)
	var pursuing: Node2D = service.get_node("HeroSword") as Node2D
	check(pursuing.get("_move") == &"stab" and is_equal_approx(first_victim.resistance, 93.0), "Stab targets a single monster farther away")
	check(player.global_position == stationary and pursuing.global_position.distance_to(player.surface_world_position()) > 48.0, "Sword flies away to attack without player movement")
	first_victim.queue_free()
	await ticks(90)
	check(pursuing.global_position.distance_to(player.surface_world_position()) < 35.0, "Sword returns to its idle position after losing the target")
	equip(-1, -1)
	await clear()
	equip(-1, 4)
	var group: Array[ENEMY] = []
	for point: Vector2 in [Vector2(25, 0), Vector2(50, -15), Vector2(45, 20)]:
		var victim: ENEMY = target(point)
		victim.set_physics_process(false)
		group.append(victim)
	await ticks(26)
	check(service.get_node("HeroSword").get("_move") == &"longcut", "Three nearby enemies trigger the long cut")
	for victim: ENEMY in group:
		check(is_equal_approx(victim.resistance, 94.0), "The long cut hits enemies around the sword")
	equip(-1, -1)
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
	# Every manifestation supports each of the thirty I/U selections.
	service.invisible_remaining = 0.0
	player.mutation_invisible = false
	player.health = 60.0
	for manifest: int in (controller.call("available_models") as Array).size():
		controller.call("select_model", manifest)
		for infusion: int in range(CATALOG.INFUSIONS.size()):
			for mutation: int in range(CATALOG.MUTATIONS.size()):
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
