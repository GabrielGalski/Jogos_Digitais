extends SceneTree
## Real world selector, shared combat snapshots, contact/blast/DOT and channel limits.

class Target:
	extends CharacterBody2D
	var health: float = 100.0
	var last_hit_direction: Vector2 = Vector2.RIGHT
	var hits: int = 0
	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		add_to_group(&"enemy_bodies")
		var shape: CircleShape2D = CircleShape2D.new()
		shape.radius = 7.0
		var collision: CollisionShape2D = CollisionShape2D.new()
		collision.shape = shape
		add_child(collision)
	func is_alive() -> bool:
		return health > 0.0
	func get_current_health() -> float:
		return health
	func take_damage(amount: float) -> void:
		health = maxf(0.0, health - amount)
		hits += 1
	func receive_impact(direction: Vector2, _impulse: float) -> void:
		last_hit_direction = direction
	func get_projectile_hurt_capsule() -> Dictionary:
		return {"center": Vector2.ZERO, "radius": 7.0, "height": 18.0}

var failures: Array[String] = []
var arena: Node2D = null
var player: Player = null
var gun: Node2D = null
var controller: Node = null
var targets: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func settle(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func add_target(point: Vector2) -> Target:
	var target: Target = Target.new()
	arena.add_child(target)
	target.global_position = point
	targets.append(target)
	return target


func clear_fixture() -> void:
	controller.call("cancel_attacks")
	for target: Node in targets:
		if is_instance_valid(target): target.queue_free()
	targets.clear()
	await settle()


func aim() -> Vector2:
	var point: Vector2 = player.surface_world_position() + Vector2(220, 0)
	gun.set("aim_screen_override", root.get_canvas_transform() * point)
	gun.set("shot_recoil", 0.0)
	gun.call("_update_rig", 0.0)
	return (gun.get_node("WeaponPivot/Muzzle") as Marker2D).global_position


func select(index: int) -> Vector2:
	check(bool(controller.call("select_model", index)), "Model can be equipped: " + str(index))
	return aim()


func _run() -> void:
	root.size = Vector2i(960, 540)
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	await create_timer(0.9).timeout
	player = arena.get_node("Nox") as Player
	gun = player.get_node("BoosterShooter") as Node2D
	controller = player.get_node("GameplayKit/Manifestations")
	player.set_physics_process(false)
	gun.set_process(false)
	player.get_node("GameplayKit").set_process(false)
	player.get_node("GameplayKit/GameplayCameraRig").set_process(false)
	player.intro_locked = false
	gun.call("set_combat_enabled", true)
	var loadout: CardLoadout = (gun.get("card_runtime") as CardCombatRuntime).copy_loadout()
	loadout.infusion = null
	loadout.mutation = null
	gun.call("equip_cards", loadout)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	var zoom: Vector2 = camera.zoom
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_BACKSPACE
	key.physical_keycode = KEY_BACKSPACE
	key.pressed = true
	Input.parse_input_event(key.duplicate() as InputEventKey)
	await process_frame
	check(not paused, "Backspace no longer opens equipment remotely")
	controller.call("open_equipment_menu")
	await process_frame
	check(paused and (controller.call("selected_model") as ProceduralManifestationModel).code() == &"M01", "Equipment entry preserves the selected weapon")
	key.echo = true
	Input.parse_input_event(key.duplicate() as InputEventKey)
	await process_frame
	check(paused, "Held Backspace does not close the menu")
	key.echo = false
	key.pressed = false
	Input.parse_input_event(key.duplicate() as InputEventKey)
	key.pressed = true
	Input.parse_input_event(key.duplicate() as InputEventKey)
	await settle()
	check(not paused, "A fresh Backspace closes equipment")
	check(camera.zoom.is_equal_approx(zoom), "Equipment keeps the balanced lighting and camera framing")
	_palette_contracts()
	var origin: Vector2 = select(0)
	var direct: Target = add_target(origin + Vector2(70, 0))
	await settle()
	var shot: Node2D = gun.call("fire_once") as Node2D
	check(shot != null and gun.call("fire_once") == null, "M01 emits once and respects its existing cooldown")
	await create_timer(0.3).timeout
	check(is_equal_approx(direct.health, 97.0) and direct.hits == 1, "M01 deals exactly one primary hit")
	await clear_fixture()
	origin = select(1)
	var primary: Target = add_target(origin + Vector2(60, 0))
	var nearby: Target = add_target(origin + Vector2(60, 19))
	var outside: Target = add_target(origin + Vector2(60, 60))
	var pierced_a: Target = add_target(origin + Vector2(109, 0))
	var pierced_b: Target = add_target(origin + Vector2(114, 0))
	var stop_wall: StaticBody2D = StaticBody2D.new()
	stop_wall.collision_layer = 1
	var stop_shape: RectangleShape2D = RectangleShape2D.new()
	stop_shape.size = Vector2(8, 54)
	var stop_collision: CollisionShape2D = CollisionShape2D.new()
	stop_collision.shape = stop_shape
	stop_wall.add_child(stop_collision)
	arena.add_child(stop_wall)
	stop_wall.global_position = origin + Vector2(150, 0)
	targets.append(stop_wall)
	var behind_wall: Target = add_target(origin + Vector2(190, 0))
	await settle()
	shot = gun.call("fire_once") as Node2D
	var mass: CardAttack = shot.get("attack") as CardAttack
	check(is_equal_approx(mass.fire_interval, 0.56 / 0.9975) and is_equal_approx(mass.projectile_speed, 897.75), "M02 uses the adjusted cadence and projectile speed")
	await settle(8)
	check(is_equal_approx(primary.health, 92.5) and primary.hits == 1 and is_equal_approx(nearby.health, 92.5), "M02 triggers the first impact blast and damages each enemy once")
	check(pierced_a.hits == 1 and pierced_b.hits == 1, "M02 pierces two subsequent bodies in the same sweep")
	await settle(6)
	check(outside.health == 100.0 and behind_wall.health == 100.0 and not is_instance_valid(shot), "M02 blast stays bounded and the projectile stops at terrain")
	await clear_fixture()
	origin = select(3)
	shot = gun.call("fire_once") as Node2D
	var spike_direction: Vector2 = shot.get("direction") as Vector2
	var attached: Target = add_target(shot.global_position + spike_direction * 55.0)
	await settle()
	await create_timer(0.3).timeout
	check(is_instance_valid(shot) and str(shot.get("phase")) == "attached", "M06 sticks to a surviving target")
	await create_timer(0.7).timeout
	check(attached.health <= 95.0 and attached.health >= 94.0, "M06 adds periodic damage after its primary hit")
	await clear_fixture()
	origin = select(4)
	var fire_target: Target = add_target(origin + (gun.get("aim_direction") as Vector2) * 20.0)
	await settle()
	shot = gun.call("fire_once") as Node2D
	var origins: Dictionary = {}
	var aims: Dictionary = {}
	var volley: CardAttack = shot.get("attack") as CardAttack
	for pellet: Node2D in get_nodes_in_group(&"manifestation_projectiles"):
		origins[pellet.global_position] = true
		aims[pellet.get("direction")] = true
		var sprite: Sprite2D = pellet.get_node("ProceduralVisual/Core32") as Sprite2D
		check(pellet.get("attack") == volley and sprite.texture.resource_path.ends_with("/projectile/base.png"), "Each pellet uses the authored art and shared emission snapshot")
	check(origins.size() == 5 and aims.size() == 5 and gun.call("fire_once") == null, "One M07 shot emits five pellets with separate launch positions and angles")
	await create_timer(0.22).timeout
	check(fire_target.hits >= 3 and is_equal_approx(fire_target.health, 100.0 - 1.2 * float(fire_target.hits)), "Multiple pellets deal damage to the same target at close range")
	await clear_fixture()
	origin = select(4)
	var distant: Target = add_target(origin + Vector2(155, 0))
	await settle()
	shot = gun.call("fire_once") as Node2D
	if "--capture" in OS.get_cmdline_user_args():
		await settle(6)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://output/card_effects")
		root.get_texture().get_image().save_png("res://output/card_effects/09-efreeti-shotgun.png")
	await create_timer(0.32).timeout
	check(not is_instance_valid(shot) and distant.health == 100.0, "M07 expires at the existing quarter-second lifetime")
	await clear_fixture()
	origin = select(6)
	var basilisk: ProceduralManifestationModel = controller.call("selected_model") as ProceduralManifestationModel
	var slime: ManifestationCard = (controller.get("MODELS")[0] as ProceduralManifestationModel).card
	check(basilisk.code() == &"M05" and basilisk.card.display_name == "Fragmentos de Basilisco", "The new manifestation keeps the M05 identity")
	check(is_equal_approx(basilisk.card.projectile_speed * basilisk.card.projectile_lifetime, slime.projectile_speed * slime.projectile_lifetime), "Basilisk stones travel the same distance as a Slime Drop")
	check(is_equal_approx(basilisk.card.fire_interval * 0.9975, slime.fire_interval), "Basilisk firing rate is 0.25 percent below Slime Drops")
	shot = gun.call("fire_once") as Node2D
	var first_fan: Array[Vector2] = []
	var forward: Vector2 = gun.get("aim_direction") as Vector2
	for stone: Node2D in get_nodes_in_group(&"manifestation_projectiles"):
		var travel_aim: Vector2 = stone.get("direction") as Vector2
		first_fan.append(travel_aim)
		check(travel_aim.dot(forward) >= cos(deg_to_rad(42.01)), "Basilisk stones stay in the forward cone")
	check(first_fan.size() == 5, "Basilisk launches five separate stones")
	if "--capture" in OS.get_cmdline_user_args():
		await settle(9)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/card_effects/11-basilisk-fragments.png")
	await clear_fixture()
	select(6)
	gun.call("fire_once")
	var next_fan: Array[Vector2] = []
	for stone: Node2D in get_nodes_in_group(&"manifestation_projectiles"):
		next_fan.append(stone.get("direction") as Vector2)
	check(next_fan.size() == 5 and first_fan != next_fan, "Basilisk chooses fresh directions on each shot")
	await clear_fixture()
	origin = select(2)
	var laser_target: Target = add_target(origin + Vector2(100, 0))
	await settle()
	controller.call("set_trigger", true)
	await create_timer(0.4).timeout
	controller.call("set_trigger", false)
	await settle()
	var health_after_laser: float = laser_target.health
	check(health_after_laser <= 97.0 and health_after_laser >= 95.0, "M04 applies continuous damage at its own tick interval")
	await create_timer(0.2).timeout
	check(laser_target.health == health_after_laser, "Releasing the beam stops damage immediately")
	await clear_fixture()
	origin = select(2)
	var covered: Target = add_target(origin + Vector2(90, 0))
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape: RectangleShape2D = RectangleShape2D.new()
	wall_shape.size = Vector2(8, 64)
	var wall_collider: CollisionShape2D = CollisionShape2D.new()
	wall_collider.shape = wall_shape
	wall.add_child(wall_collider)
	arena.add_child(wall)
	wall.global_position = origin + Vector2(40, 0)
	targets.append(wall)
	await settle()
	controller.call("set_trigger", true)
	await create_timer(0.25).timeout
	check(covered.health == 100.0, "M04 stops at map geometry rather than damaging through it")
	controller.call("set_trigger", false)
	await clear_fixture()
	origin = select(5)
	var in_cone: Target = add_target(origin + Vector2(70, 0))
	var beside_cone: Target = add_target(origin + Vector2(70, 45))
	await settle()
	controller.call("set_trigger", true)
	await create_timer(0.4).timeout
	var flame: Node2D = controller.get("channel") as Node2D
	var jet: CPUParticles2D = flame.get_node_or_null("Jet") as CPUParticles2D if is_instance_valid(flame) else null
	var sparks: CPUParticles2D = flame.get_node_or_null("EdgeSparks") as CPUParticles2D if is_instance_valid(flame) else null
	check(jet != null and jet.emitting and jet.amount == 144 and not jet.local_coords
		and jet.color_ramp.sample(0.0).is_equal_approx(Color("#fffc40")),
		"M08 uses the restored world-space flame particles")
	check(sparks != null and sparks.emitting and sparks.amount == 32, "M08 emits the restored sparks")
	check(in_cone.health < 100.0 and beside_cone.health == 100.0, "M08 grows a directional damage cone")
	controller.call("set_trigger", false)
	await settle()
	check(is_instance_valid(jet) and is_instance_valid(sparks) and not jet.emitting and not sparks.emitting and flame.visible,
		"M08 keeps only its dissipating particles on release")
	var health_after_stream: float = in_cone.health
	await create_timer(0.2).timeout
	check(in_cone.health == health_after_stream, "Dissipating flames do not keep dealing damage")
	await clear_fixture()
	await _combination_contract()
	await _real_input_contract()
	check(not controller.get("MODELS").any(func(model: ProceduralManifestationModel) -> bool: return model.code() == &"M03"), "M03 remains outside the implemented selector")
	controller.call("cancel_attacks")
	print("PROCEDURAL_WEAPONS_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)


func _palette_contracts() -> void:
	var factory: ProceduralWeaponSpriteFactory = controller.get("sprites") as ProceduralWeaponSpriteFactory
	for model: ProceduralManifestationModel in controller.get("MODELS"):
		if model.family == ProceduralManifestationModel.Family.STREAM:
			continue
		if model.projectile_texture != null:
			var art: Image = model.projectile_texture.get_image()
			check(art.get_used_rect().size == Vector2i(8, 8) and is_equal_approx(model.visual_scale, 0.75), "Authored pellet has a six-pixel display size: " + String(model.code()))
			continue
		var presentation: Texture2D = factory.texture_for(model, 0, Vector2.RIGHT)
		check(presentation.get_size() == Vector2(96, 96), "Smooth presentation uses 3x raster density: " + String(model.code()))
		check(model.visual_scale >= 0.3 and model.visual_scale <= 0.65, "Compact presentation remains independent of collision: " + String(model.code()))
		var palette: Dictionary = {model.shadow_color.to_rgba32(): true, model.body_color.to_rgba32(): true, model.core_color.to_rgba32(): true}
		for frame: int in range(4):
			for orientation: int in [0, 4, 8, 13]:
				var image: Image = factory.rasterize(model, frame, orientation)
				var valid: bool = image.get_size() == Vector2i(32, 32)
				var count: int = 0
				for y: int in range(32):
					for x: int in range(32):
						var color: Color = image.get_pixel(x, y)
						if color.a == 0.0: continue
						count += 1
						valid = valid and color.a == 1.0 and palette.has(color.to_rgba32())
				check(valid and count > 5, "32px, three-color raster: " + String(model.code()))
	check(factory.cache_size() <= factory.CACHE_LIMIT, "Texture cache has a fixed bound")


func _combination_contract() -> void:
	var origin: Vector2 = select(2)
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var loadout: CardLoadout = runtime.copy_loadout()
	loadout.infusion = load("res://resources/cards/golem_core.tres") as InfusionCard
	loadout.mutation = load("res://resources/cards/fury_heart.tres") as MutationCard
	gun.call("equip_cards", loadout)
	check(bool(controller.call("select_model", 0)), "Equipment command accepts existing Infusion and Mutation")
	check((gun.get("card_runtime") as CardCombatRuntime).copy_loadout().infusion != null, "Cycling preserves equipped secondary cards")
	origin = aim()
	var old_shot: Node2D = gun.call("fire_once") as Node2D
	old_shot.set_physics_process(false)
	var old_attack: CardAttack = old_shot.get("attack") as CardAttack
	controller.call("select_model", 1)
	check(old_attack.manifestation_id == &"M01" and is_equal_approx(old_attack.damage, 3.0), "An airborne attack keeps its original model snapshot after a swap")
	var victim: Target = add_target(origin + Vector2(50, 0))
	victim.health = 1.0
	old_attack.apply_primary_hit(victim, victim.global_position, Vector2.RIGHT, gun.get("effects") as CombatEffects)
	check((gun.get("card_runtime") as CardCombatRuntime).mutation_remaining > 0.0, "Changing only the manifestation preserves kill credit for the same mutation")
	controller.call("select_mutation", 1)
	controller.call("select_mutation", 0)
	victim = add_target(origin + Vector2(65, 0))
	victim.health = 1.0
	old_attack.apply_secondary_hit(victim, 3.0, Vector2.RIGHT, gun.get("effects") as CombatEffects)
	check((gun.get("card_runtime") as CardCombatRuntime).mutation_remaining == 0.0, "An old attack cannot activate a mutation equipped after its emission")
	await clear_fixture()


func mouse(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _real_input_contract() -> void:
	var fired_models: Array[StringName] = []
	var record_shot: Callable = func() -> void:
		fired_models.append((controller.call("selected_model") as ProceduralManifestationModel).code())
	gun.connect("shot_fired", record_shot)
	select(0)
	gun.set_process(true)
	mouse(false)
	await settle()
	mouse(true)
	var deadline: int = Time.get_ticks_msec() + 1000
	while not fired_models.has(&"M01") and Time.get_ticks_msec() < deadline:
		await physics_frame
	check(fired_models.has(&"M01"), "Real mouse input reaches the procedural executor")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_BACKSPACE
	key.physical_keycode = KEY_BACKSPACE
	key.pressed = true
	controller.call("open_equipment_menu")
	await create_timer(0.16).timeout
	controller.call("select_model", 1)
	Input.parse_input_event(key.duplicate() as InputEventKey)
	await settle()
	check(not fired_models.has(&"M02"), "Holding fire through a swap requires a release before the next model")
	mouse(false)
	await settle()
	mouse(true)
	deadline = Time.get_ticks_msec() + 1000
	while not fired_models.has(&"M02") and Time.get_ticks_msec() < deadline:
		await physics_frame
	check(fired_models.has(&"M02"), "Release and press resumes shooting with the selected model")
	mouse(false)
	key.pressed = false
	Input.parse_input_event(key.duplicate() as InputEventKey)
	gun.disconnect("shot_fired", record_shot)
	gun.set_process(false)
	await clear_fixture()
