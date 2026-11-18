extends SceneTree
## Grazing hits, torso, muzzle overlaps, fast bullets and wall occlusion on real enemies.

const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const MINION: PackedScene = preload("res://scenes/enemies/minotaur.tscn")
const SLIME: PackedScene = preload("res://scenes/dungeon/manifestation_projectile.tscn")
const RAPID: PackedScene = preload("res://scenes/combat/projectiles/rapid_electric_bullet.tscn")
const BOSS: Script = preload("res://scripts/asterion_skybreaker.gd")
var checks: int = 0
var failures: int = 0
var effects: CombatEffects = null


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("[PROJECTILE CONTACT] " + message)


func _run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	var boss: Node2D = current_scene.get_node("MinotaurChair") as Node2D
	boss.set("auto_start_encounter", false)
	await create_timer(3.8).timeout
	var player: Player = current_scene.get_node("Mox") as Player
	player.set_physics_process(false)
	player.position = Vector2(-40, 80)
	player.reset_physics_interpolation()
	var kit: Node2D = player.get_node("GameplayKit") as Node2D
	kit.set_process(false)
	player.get_node("BoosterShooter").set_process(false)
	effects = kit.get("effects") as CombatEffects
	var enemy: Minotaur = _spawn(Vector2(70, 80))
	await physics_frame
	check(is_equal_approx((enemy.body_shape.shape as CircleShape2D).radius, 11.0), "minion physical radius stays 11")
	check(enemy.get_projectile_hurt_capsule().get("radius") == 15.0 and enemy.get_projectile_hurt_capsule().get("height") == 34.0, "damage volume covers the authored 32px body")
	var raw: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(Vector2(0, 60), Vector2(130, 60), 5)
	check(current_scene.get_world_2d().direct_space_state.intersect_ray(raw).is_empty(), "old center-only test misses grazing sprite")
	check(_sweep(Vector2(0, 60), Vector2(130, 60), 0.0).is_empty(), "ray center outside the receiving capsule")
	check(_sweep(Vector2(0, 60), Vector2(130, 60), 3.0).get("collider") == enemy, "bullet width catches a real edge graze")
	check(_sweep(Vector2(0, 55), Vector2(130, 55), 3.0).is_empty(), "genuinely outside shot still misses")
	var shot: Node2D = _slime(Vector2(0, 60))
	shot.call("_physics_process", 0.5)
	check(is_equal_approx(enemy.resistance, 9.0) and shot.get("phase") == &"impact_ending", "real fast slime deals grazing damage without tunneling")
	shot.call("_physics_process", 0.02)
	check(is_equal_approx(enemy.resistance, 9.0), "one contact never deals duplicate damage")
	shot.free()
	# At near-melee distance the muzzle can already be inside the visual body.
	enemy.position = Vector2(30, 80)
	enemy.resistance = 12.0
	shot = _slime(Vector2(26, 66))
	shot.call("_physics_process", 0.016)
	check(is_equal_approx(enemy.resistance, 9.0) and bool(shot.get("consumed")), "spawn-overlap at close range hits immediately")
	shot.free()
	# The old ray also misses when its origin is already inside the physical circle.
	enemy.resistance = 12.0
	raw = PhysicsRayQueryParameters2D.create(Vector2(26, 80), Vector2(34, 80), 5)
	check(current_scene.get_world_2d().direct_space_state.intersect_ray(raw).is_empty(), "old ray ignores a muzzle starting inside the physical enemy")
	shot = _slime(Vector2(26, 80))
	shot.call("_physics_process", 0.016)
	check(is_equal_approx(enemy.resistance, 9.0) and bool(shot.get("consumed")), "close physical-overlap shot also registers immediately")
	shot.free()
	enemy.set_empowered(true)
	check(_sweep(Vector2(0, 60), Vector2(70, 60), 3.0).get("collider") == enemy, "empowered minion has the same forgiving contact")
	enemy.position = Vector2(70, 80)
	var behind: Minotaur = _spawn(Vector2(110, 80))
	await physics_frame
	check(_sweep(Vector2(0, 66), Vector2(140, 66), 3.0).get("collider") == enemy, "front enemy wins regardless of group order")
	# Rapid fallback uses the same receiver, rather than a different invisible hit area.
	var rapid: RapidElectricBullet = RAPID.instantiate() as RapidElectricBullet
	current_scene.add_child(rapid)
	rapid.position = Vector2(0, 60)
	rapid.set_physics_process(false)
	rapid.card_attack = _attack()
	rapid.setup(Vector2.RIGHT, effects)
	rapid.obstacle_mask = 1
	rapid.movement_speed = 360.0
	rapid.call("_physics_process", 0.5)
	check(is_equal_approx(enemy.resistance, 6.0) and is_equal_approx(behind.resistance, 12.0), "rapid projectile uses same broad first contact")
	rapid.free()
	behind.free()
	# Expanded hurtboxes cannot stick through cover and bypass a wall.
	enemy.position = Vector2(63, 80)
	var wall: StaticBody2D = StaticBody2D.new()
	wall.position = Vector2(50, 80)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(4, 60)
	shape.shape = rectangle
	wall.add_child(shape)
	current_scene.add_child(wall)
	await physics_frame
	check(_sweep(Vector2(0, 80), Vector2(130, 80), 3.0).get("collider") == wall, "wall wins even if generous capsule extends in front of it")
	var before: float = enemy.resistance
	shot = _slime(Vector2(0, 80))
	shot.call("_physics_process", 0.5)
	check(is_equal_approx(enemy.resistance, before) and bool(shot.get("consumed")), "live shot cannot damage through wall")
	shot.free()
	wall.free()
	enemy.free()
	# Actual Asterion actor: hits above his old ground-radius now reach the torso.
	var actor: CharacterBody2D = boss.get_node("Actor") as CharacterBody2D
	actor.position = Vector2.ZERO
	actor.global_position = Vector2(70, 80)
	actor.show()
	boss.set("state", BOSS.State.CHASE)
	boss.set("health", 250.0)
	boss.set_physics_process(false)
	var body_shape: CollisionShape2D = actor.get_node("BodyCollision") as CollisionShape2D
	body_shape.disabled = false
	await physics_frame
	check(is_equal_approx((body_shape.shape as CircleShape2D).radius, 12.0), "boss physical radius stays 12")
	check(float(actor.call("get_separation_radius")) == 12.0, "boss navigation/separation stays unchanged")
	check(_sweep(Vector2(0, 50), Vector2(130, 50), 3.0).get("collider") == actor, "boss torso is a real projectile receiver")
	check(_sweep(Vector2(0, 80), Vector2(130, 80), 3.0).get("collider") == actor, "boss feet remain covered")
	shot = _slime(Vector2(0, 50))
	shot.call("_physics_process", 0.5)
	check(is_equal_approx(float(boss.get("health")), 247.0), "real torso hit deals unchanged 3 damage to Asterion")
	shot.free()
	boss.set("state", BOSS.State.OFFSCREEN)
	body_shape.disabled = true
	await physics_frame
	check(_sweep(Vector2(0, 50), Vector2(130, 50), 3.0).is_empty(), "airborne/invulnerable boss does not gain an invisible receiving body")
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]:
		var hit: Dictionary = CONTACTS._capsule_hit(-direction * 60.0, direction * 60.0, Vector2.ZERO, 18.0, 2.0)
		check(not hit.is_empty() and (hit.get("normal") as Vector2).dot(direction) < 0.0, "swept capsule supports axis/diagonal %s" % direction)
	print("PROJECTILE_CONTACT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _sweep(origin: Vector2, endpoint: Vector2, radius: float) -> Dictionary:
	return CONTACTS.sweep(self, current_scene.get_world_2d().direct_space_state, origin, endpoint, 5, radius)


func _spawn(at: Vector2) -> Minotaur:
	var enemy: Minotaur = MINION.instantiate() as Minotaur
	enemy.position = at
	current_scene.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _attack() -> CardAttack:
	var attack: CardAttack = CardAttack.new()
	attack.damage = 3.0
	attack.projectile_speed = 360.0
	attack.projectile_lifetime = 5.0
	return attack


func _slime(at: Vector2) -> Node2D:
	var shot: Node2D = SLIME.instantiate() as Node2D
	current_scene.add_child(shot)
	shot.position = at
	shot.set_physics_process(false)
	shot.call("configure", &"M01", Vector2.RIGHT, _attack(), effects)
	return shot
