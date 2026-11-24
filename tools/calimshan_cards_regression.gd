extends SceneTree
## Exercises the new cards through the real player, projectile driver and combat service.

const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const KIT: Script = preload("res://scripts/combat/player_gameplay_kit.gd")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const FRAMES: SpriteFrames = preload("res://resources/visual/calimshan_frames.tres")

class Target extends CharacterBody2D:
	var health: float = 100.0
	var hits: int = 0
	var shielded: bool = false

	func _ready() -> void:
		add_to_group(&"enemy_bodies")
		collision_layer = 4
		collision_mask = 0
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 5.0
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.shape = circle
		add_child(collider)

	func is_alive() -> bool:
		return health > 0.0

	func get_current_health() -> float:
		return health

	func get_projectile_hurt_capsule() -> Dictionary:
		return {"center": Vector2.ZERO, "radius": 5.0, "height": 12.0}

	func take_damage(amount: float) -> void:
		if shielded:
			return
		health = maxf(0.0, health - amount)
		hits += 1

var arena: Node2D
var player: Player
var gun: Node2D
var driver: Node
var elements: Node
var effects: CombatEffects
var runtime: CardCombatRuntime
var fixtures: Array[Target] = []
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 540)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	player = PLAYER.instantiate() as Player
	arena.add_child(player)
	var kit: Node2D = KIT.new()
	kit.name = "GameplayKit"
	kit.set("world_bounds", player.arena_bounds)
	player.add_child(kit)
	kit.set_process(false)
	player.set_physics_process(false)
	gun = player.get_node("BoosterShooter") as Node2D
	driver = kit.get_node("Manifestations")
	elements = kit.get_node("CardEffects/Calimshan")
	effects = kit.get_node("ShooterEffects") as CombatEffects
	runtime = gun.get("card_runtime") as CardCombatRuntime
	await _ticks(3)
	check(CATALOG.PACK_CODES[CATALOG.DRAGON_PACK - 1].size() == 6, "The Dragon pack has six cards")
	for clip: StringName in FRAMES.get_animation_names():
		check(FRAMES.get_frame_count(clip) > 1, "Authored animation loads: " + String(clip))
	await _test_prism()
	await _test_lightning()
	await _test_burn()
	await _test_ice()
	await _test_dash_fire()
	await _test_runes()
	await _test_rune_detour()
	await _clear()
	var combinations: int = 0
	for manifestation: int in range(CATALOG.MANIFESTATIONS.size()):
		driver.call("select_model", manifestation)
		for infusion: int in range(CATALOG.INFUSIONS.size()):
			driver.call("select_infusion", infusion)
			for mutation: int in range(CATALOG.MUTATIONS.size()):
				driver.call("select_mutation", mutation)
				var shot: CardAttack = runtime.create_attack()
				if shot != null and shot.infusion_effect == infusion and runtime.mutation_effect() == mutation \
						and shot.manifestation_id == CATALOG.MANIFESTATIONS[manifestation].code():
					combinations += 1
	var expected: int = CATALOG.MANIFESTATIONS.size() * CATALOG.INFUSIONS.size() * CATALOG.MUTATIONS.size()
	check(combinations == expected, "Each three-card selection produces the expected snapshot")
	print("CALIMSHAN ", JSON.stringify({"checks": checks, "combinations": combinations, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _test_prism() -> void:
	await _clear()
	driver.call("select_model", 7)
	var at: Vector2 = _aim_right()
	var close: Target = _target(at + Vector2(25, 0))
	await _ticks(2)
	var shot: Node2D = gun.call("fire_once") as Node2D
	check(is_instance_valid(shot), "Prism can be fired through the equipped Booster")
	await _ticks(12)
	check(is_equal_approx(close.health, 96.0) and close.hits == 1 and get_nodes_in_group(&"player_projectiles").is_empty(),
		"A close hit deals one crystal impact without splitting")
	await _clear()
	at = _aim_right()
	var above: Target = _target(at + Vector2(91, -11))
	var below: Target = _target(at + Vector2(91, 11))
	await _ticks(2)
	shot = gun.call("fire_once") as Node2D
	var snapshot: CardAttack = shot.get("attack") as CardAttack if is_instance_valid(shot) else null
	await _ticks(9)
	var shards: Array[Node] = get_nodes_in_group(&"manifestation_projectiles")
	check(shards.size() == 2 and shards.all(func(shard: Node) -> bool: return shard.get("attack") == snapshot),
		"Two shards inherit the original attack snapshot")
	await _ticks(15)
	check(is_equal_approx(above.health, 97.4) and is_equal_approx(below.health, 97.4), "The shards hit distinct targets")


func _test_lightning() -> void:
	await _clear()
	driver.call("select_infusion", InfusionCard.LIGHTNING)
	var struck: Target = _target(Vector2(45, 0))
	await _ticks(3)
	check(is_equal_approx(struck.health, 95.0) and struck.is_in_group(&"immobilized_enemies") and _clip_count(&"lightning_a") == 1,
		"The first authored bolt damages and stuns")
	var nearby: Target = _target(Vector2(74, 0))
	var far: Target = _target(Vector2(129, 0))
	effects.apply_hit(struck, 200.0, Vector2.ZERO, 0.0)
	await _ticks(3)
	check(is_equal_approx(nearby.health, 97.0) and far.health == 100.0 and _clip_count(&"discharge") == 1,
		"A kill during the mark sends the authored discharge only to nearby targets")
	await _clear()
	driver.call("select_infusion", InfusionCard.LIGHTNING)
	struck = _target(Vector2(45, 0))
	await _ticks(3)
	check(_clip_count(&"lightning_b") == 1, "The next bolt uses the other authored animation")
	await _ticks(122)
	check(not struck.is_in_group(&"immobilized_enemies"), "Lightning stun expires")
	nearby = _target(Vector2(70, 0))
	effects.apply_hit(struck, 200.0, Vector2.ZERO, 0.0)
	await _ticks(2)
	check(nearby.health == 100.0, "A kill after stun expiry cannot discharge")


func _test_burn() -> void:
	await _clear()
	driver.call("select_infusion", InfusionCard.FIRE)
	var ignited: Target = _target(Vector2(40, 0))
	var first: Target = _target(Vector2(53, 0))
	var second: Target = _target(Vector2(66, 0))
	var third: Target = _target(Vector2(79, 0))
	var shot: CardAttack = runtime.create_attack()
	shot.apply_primary_hit(ignited, ignited.global_position, Vector2.RIGHT, effects)
	var next: CardAttack = runtime.create_attack()
	next.apply_primary_hit(third, third.global_position, Vector2.RIGHT, effects)
	var third_health: float = third.health
	var smoke: AnimatedSprite2D = ignited.get_node_or_null("Burn") as AnimatedSprite2D
	check(smoke != null and smoke.z_index < 0, "Burn smoke follows and draws behind its target")
	check(_clip_count(&"burn") == 1 and float(runtime.cooldowns.get(&"I07", 0.0)) > 2.0,
		"A confirmed shot consumes the burn cooldown once")
	driver.call("select_infusion", -1)
	await _ticks(75)
	check(_clip_count(&"burn") == 3 and first.health < 100.0 and second.health < 100.0 and third.health == third_health,
		"Burn persists through a swap and spreads once to up to two neighbors")


func _test_ice() -> void:
	await _clear()
	driver.call("select_infusion", InfusionCard.ICE)
	var target: Target = _target(Vector2(44, 0))
	var protected: Target = _target(Vector2(44, 7))
	protected.shielded = true
	await _ticks(3)
	check(target.health == 100.0 and _clip_count(&"spikes") == 0, "Ice warns before it strikes")
	await _ticks(18)
	check(is_equal_approx(target.health, 97.0) and target.is_in_group(&"frozen_enemies")
		and target.is_in_group(&"immobilized_enemies") and _clip_count(&"frozen") == 1,
		"Spikes freeze at impact and start the animated overhead status")
	check(protected.health == 100.0 and not protected.is_in_group(&"immobilized_enemies"), "Immune targets are not frozen by a rejected hit")
	effects.apply_hit(target, 10.0, Vector2.ZERO, 0.0)
	check(is_equal_approx(target.health, 86.867), "Frozen targets take exactly 1.33 percent more damage")
	await _ticks(135)
	check(not target.is_in_group(&"frozen_enemies") and not target.is_in_group(&"immobilized_enemies")
		and _clip_count(&"frozen") == 0, "Freeze, vulnerability and overlay clear together")


func _test_dash_fire() -> void:
	await _clear()
	driver.call("select_infusion", InfusionCard.FIRE)
	driver.call("select_mutation", MutationCard.ASH_STEP)
	var center: Target = _target(Vector2(41, 0))
	var away: Target = _target(Vector2(41, 34))
	player.set_physics_process(true)
	check(player.try_dash(Vector2.RIGHT), "Real dash triggers Ash Step")
	await _ticks(21)
	player.set_physics_process(false)
	check(player.global_position.x > 80.0 and is_equal_approx(center.health, 98.0) and away.health == 100.0,
		"The fire path hits once on entry and follows the dash")
	await _ticks(28)
	check(center.health < 98.0 and _clip_count(&"burn") == 1, "Ash Step ignites with the shared non-spreading burn")
	var shot: CardAttack = runtime.create_attack()
	shot.apply_primary_hit(center, center.global_position, Vector2.RIGHT, effects)
	check(shot.manifestation_id == &"M09" and _clip_count(&"burn") == 1, "Prism, fire infusion and dash share one burn per enemy")
	await _ticks(60)
	check(away.health < 100.0 and _clip_count(&"burn") == 2, "The charged hit enables spreading on the existing dash burn")


func _test_runes() -> void:
	await _clear()
	driver.call("select_mutation", MutationCard.PRIMORDIAL_CONVERGENCE)
	_key_f()
	await _ticks(2)
	check(elements.call("rune_count") == 1, "F places the first authored rune")
	player.global_position = Vector2(0, -86)
	await _ticks(2)
	_key_f()
	await _ticks(2)
	check(elements.call("rune_count") == 2 and elements.has_node("PrimordialLightning"), "F places the second rune and draws the arc")
	var crossing: Target = _target(Vector2(-13, -42))
	await _ticks(2)
	crossing.global_position.x = 0.0
	await _ticks(8)
	check(is_equal_approx(crossing.health, 94.0) and crossing.is_in_group(&"immobilized_enemies"),
		"Crossing the arc deals its damage and stun once while the enemy stays in contact")
	_key_f()
	await _ticks(2)
	check(elements.call("rune_count") == 0 and not elements.has_node("PrimordialLightning"), "F disarms both runes")
	player.global_position = Vector2.ZERO
	_key_f()
	await _ticks(2)
	player.global_position = Vector2(190, 0)
	await _ticks(2)
	check(elements.call("rune_count") == 0, "Walking away resets a pending rune")
	player.global_position = Vector2.ZERO
	await _ticks(2)
	_key_f()
	await _ticks(2)
	_key_f()
	await _ticks(2)
	check(elements.call("rune_count") == 2 and elements.has_node("PrimordialLightning"), "Two presses in place link to a nearby clear point")


func _test_rune_detour() -> void:
	await _clear()
	var wall: StaticBody2D = StaticBody2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(28, 156)
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(68, 3)
	arena.add_child(wall)
	await _ticks(2)
	driver.call("select_mutation", MutationCard.PRIMORDIAL_CONVERGENCE)
	_key_f()
	await _ticks(2)
	player.global_position = Vector2(150, 0)
	await _ticks(2)
	_key_f()
	await _ticks(2)
	var route: PackedVector2Array = elements.get("_rune_path")
	var beam: Node2D = elements.get_node_or_null("PrimordialLightning") as Node2D
	check(elements.call("rune_count") == 2 and route.size() >= 3 and is_instance_valid(beam),
		"The second rune links around a wall within disarm range")
	if route.size() >= 3 and is_instance_valid(beam):
		var visual_route: PackedVector2Array = beam.get("lightning_path")
		check(visual_route.size() == route.size() and visual_route[-1].is_equal_approx(route[-1] - route[0]),
			"The lightning draws the routed turns and ends at the actual rune")
		var collision_free: bool = true
		for index: int in range(1, route.size()):
			var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(route[index - 1], route[index], 1, [player.get_rid()])
			collision_free = collision_free and arena.get_world_2d().direct_space_state.intersect_ray(query).is_empty()
		check(collision_free, "Every segment of the detour clears static geometry")
		var midpoint: Vector2 = route[1].lerp(route[2], 0.5)
		var side: Vector2 = route[1].direction_to(route[2]).orthogonal() * 13.0
		var crossing: Target = _target(midpoint + side)
		var across_wall: Target = _target(wall.position)
		await _ticks(3)
		crossing.global_position = midpoint - side
		await _ticks(3)
		check(crossing.health == 94.0 and across_wall.health == 100.0,
			"A fast crossing hits the routed beam and the blocked straight line deals no damage")
	wall.queue_free()


func _ticks(frames: int) -> void:
	for _index: int in range(frames):
		await physics_frame
	await process_frame


func _clear() -> void:
	driver.call("select_infusion", -1)
	driver.call("select_mutation", -1)
	driver.call("cancel_attacks")
	for target: Target in fixtures:
		if is_instance_valid(target):
			target.queue_free()
	fixtures.clear()
	elements.call("_clear")
	runtime.cooldowns.clear()
	player.global_position = Vector2.ZERO
	player.snap_floor_height()
	gun.set("cooldown", 0.0)
	await _ticks(2)


func _aim_right() -> Vector2:
	gun.set("aim_screen_override", root.get_canvas_transform() * (player.surface_world_position() + Vector2(220, 0)))
	gun.set("shot_recoil", 0.0)
	gun.call("_update_rig", 0.0)
	return (gun.get_node("WeaponPivot/Muzzle") as Marker2D).global_position


func _target(point: Vector2) -> Target:
	var target: Target = Target.new()
	target.position = point
	arena.add_child(target)
	fixtures.append(target)
	return target


func _clip_count(clip: StringName) -> int:
	var count: int = 0
	var children: Array[Node] = elements.get_children()
	if clip == &"burn":
		for target: Target in fixtures:
			if is_instance_valid(target):
				children.append_array(target.get_children())
	for child: Node in children:
		var sprite: AnimatedSprite2D = child as AnimatedSprite2D
		if sprite != null and sprite.animation == clip and not sprite.is_queued_for_deletion():
			count += 1
	return count


func _key_f() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	Input.parse_input_event(key)
	var release: InputEventKey = key.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
