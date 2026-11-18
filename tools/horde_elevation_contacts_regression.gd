extends SceneTree
## Projected hit reception through the same factory used by equipped weapons.
const ENEMY: Script = preload("res://scripts/enemies/open_world_horde_enemy.gd")
const CATALOG: Script = preload("res://scripts/enemies/open_world_horde_catalog.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const FACTORY: Script = preload("res://scripts/combat/manifestations/manifestation_factory.gd")
const CONTROLLER: Script = preload("res://scripts/combat/manifestations/manifestation_controller.gd")
var failures: Array[String] = []
var checks: int = 0
var world: Node2D
var player: Player
var effects: CombatEffects
var sprites: ProceduralWeaponSpriteFactory = ProceduralWeaponSpriteFactory.new()


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


func spawn(species: String, variant: Array, point: Vector2) -> ENEMY:
	var actor: ENEMY = ENEMY.new()
	actor.configure(species, player, Callable(world, "_terrain_and_warp_height"))
	actor.variant = variant
	actor.position = point
	actor.resistance = 100.0
	world.add_child(actor)
	return actor


func shoot(actor: ENEMY, model: ProceduralManifestationModel, origin: Vector2, direction: Vector2) -> void:
	var attack: CardAttack = CardAttack.new()
	attack.damage = 1.0
	attack.projectile_speed = 600.0
	attack.projectile_lifetime = 1.0
	var before: float = actor.resistance
	if model.family == ProceduralManifestationModel.Family.PROJECTILE:
		var shot: Node2D = FACTORY.projectile(model, attack, world, origin, direction, effects, player, sprites)
		shot.call("_physics_process", 0.16)
		check(actor.resistance < before, "%s hits %s at height %.1f" % [model.code(), actor.species, actor.floor_height])
		shot.free()
	else:
		var channel: Node2D = FACTORY.channel(model, world, player, sprites)
		channel.call("advance", 0.8, origin, direction, true)
		var targets: Array = channel.call("hit_targets") as Array
		check(targets.has(actor), "%s channel reaches the elevated body" % model.code())
		for target: Node2D in targets:
			attack.apply_primary_hit(target, CONTACTS.damage_center(target), direction, effects)
		check(actor.resistance < before, "%s channel applies damage" % model.code())
		channel.free()


func _run() -> void:
	world = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	world.set("warp_entry_cutscene_enabled", false)
	world.set("insect_spawns_enabled", false)
	root.add_child(world)
	for name: String in ["FlyingSkullZones", "SlimeZones"]:
		world.get_node(name).set_physics_process(false)
	current_scene = world
	while not bool(world.get("entry_complete")):
		await process_frame
	player = world.get_node("Nox") as Player
	player.set_physics_process(false)
	player.get_node("BoosterShooter").set_process(false)
	player.get_node("GameplayKit/Manifestations").set_physics_process(false)
	effects = player.get_node("GameplayKit").get("effects") as CombatEffects
	effects.camera_feedback_enabled = false
	effects.explosion_visuals_enabled = false
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	for point: Vector2 in [Vector2(1600, 1400), Vector2(1600, 880), Vector2(1384, 1120)]:
		for species: String in CATALOG.TYPES:
			for variant: Array in CATALOG.TYPES[species].bodies:
				var actor: ENEMY = spawn(species, variant, point)
				await physics_frame
				var center: Vector2 = CONTACTS.damage_center(actor)
				var sprite: Sprite2D = actor.get_node("Sprite") as Sprite2D
				check(is_equal_approx(sprite.position.y, -7.0 - roundf(actor.floor_height)), "Visual and terrain height agree")
				for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
					var start: Vector2 = center - direction * 48.0
					var end: Vector2 = center + direction * 48.0
					check(CONTACTS.sweep(self, space, start, end, 4, 1.0).get("collider") == actor, "Sweep reaches the visible body")
					shoot(actor, CONTROLLER.MODELS[0], start, direction)
				if actor.floor_height > 24.0:
					check(CONTACTS.sweep(self, space, point - Vector2(48, 0), point + Vector2(48, 0), 4, 1.0).is_empty(), "Logical movement body cannot receive an invisible hit below the sprite")
				for model: ProceduralManifestationModel in CONTROLLER.MODELS:
					shoot(actor, model, center - Vector2(48, 0), Vector2.RIGHT)
				var before: float = actor.resistance
				effects.trigger_explosion(center, 18.0, 1.0)
				check(actor.resistance < before, "Infusion explosion uses the projected receiving center")
				actor.free()
	var primary: ENEMY = spawn("goblin", CATALOG.TYPES.goblin.bodies[0], Vector2(1600, 880))
	var nearby: ENEMY = spawn("skeleton", CATALOG.TYPES.skeleton.bodies[0], Vector2(1600, 894))
	await physics_frame
	shoot(primary, CONTROLLER.MODELS[1], CONTACTS.damage_center(primary) - Vector2(48, 0), Vector2.RIGHT)
	check(nearby.resistance < 100.0, "Native blast damages neighboring bodies on the elevated castle floor")
	primary.free()
	nearby.free()
	# Moving down a real ramp updates both presentation and receiving volume.
	var descending: ENEMY = spawn("goblin", CATALOG.TYPES.goblin.bodies[0], Vector2(1384, 1064))
	var upper: float = descending.floor_height
	descending.position.y = 1176.0
	descending.sync_floor_height()
	check(descending.floor_height < upper, "Ramp traversal changes height")
	check(CONTACTS.damage_center(descending).y > descending.global_position.y - 25.0, "Receiving capsule follows the descent")
	descending.free()
	world.queue_free()
	await process_frame
	print("HORDE_ELEVATION_CONTACTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
