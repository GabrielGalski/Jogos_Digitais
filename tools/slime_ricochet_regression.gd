extends SceneTree
## Checks swept contacts, geometric reflection, damage and editable bounce budget.

class DummyEnemy extends StaticBody2D:
	var health: float = 100.0
	var last_impulse: float = 0.0
	var last_direction: Vector2 = Vector2.ZERO
	func is_alive() -> bool:
		return health > 0.0
	func take_damage(amount: float) -> void:
		health -= amount
	func receive_impact(direction: Vector2, impulse: float) -> void:
		last_direction = direction
		last_impulse = impulse

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _make_attack(damage: float = 3.0, impulse: float = 0.0) -> CardAttack:
	var attack: CardAttack = CardAttack.new()
	attack.damage = damage
	attack.projectile_speed = 180.0
	attack.projectile_lifetime = 5.0
	attack.impact_impulse = impulse
	return attack


func _run() -> void:
	var m01_card: ManifestationCard = load("res://resources/cards/preview/M01.tres") as ManifestationCard
	var m02_card: ManifestationCard = load("res://resources/cards/preview/M02.tres") as ManifestationCard
	check(is_equal_approx(m02_card.damage, m01_card.damage * 2.5), "M02 card damage is not 2.5x M01")
	check(is_equal_approx(m02_card.fire_interval, 0.42 / 0.75), "M02 cadence was not reduced by 25%")
	var world: Node2D = Node2D.new()
	root.add_child(world)
	var effects: CombatEffects = CombatEffects.new()
	effects.camera_feedback_enabled = false
	world.add_child(effects)
	var wall: StaticBody2D = StaticBody2D.new()
	wall.position = Vector2(0.0, -12.0)
	var wall_shape: CollisionShape2D = CollisionShape2D.new()
	var wall_box: RectangleShape2D = RectangleShape2D.new()
	wall_box.size = Vector2(200.0, 4.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	world.add_child(wall)
	var enemy: DummyEnemy = DummyEnemy.new()
	enemy.collision_layer = 4
	enemy.position = Vector2(12.0, 0.0)
	var enemy_shape: CollisionShape2D = CollisionShape2D.new()
	var enemy_circle: CircleShape2D = CircleShape2D.new()
	enemy_circle.radius = 5.0
	enemy_shape.shape = enemy_circle
	enemy.add_child(enemy_shape)
	world.add_child(enemy)
	enemy.add_to_group(&"enemy_bodies")
	await physics_frame

	var scene: PackedScene = load("res://scenes/dungeon/manifestation_projectile.tscn") as PackedScene
	var shot: Node2D = scene.instantiate() as Node2D
	world.add_child(shot)
	shot.set_physics_process(false)
	shot.position = Vector2.ZERO
	shot.call(&"configure", &"M01", Vector2(1.0, -1.0), _make_attack(), effects)
	shot.call(&"_physics_process", 0.09)
	var reflected: Vector2 = shot.get(&"direction") as Vector2
	var visual: Sprite2D = shot.get_node("Visual") as Sprite2D
	check(reflected.x > 0.69 and reflected.y > 0.69, "M01 did not reflect on top wall")
	check(int(shot.get(&"remaining_ricochets")) == 0, "M01 did not consume its only bounce")
	check(is_equal_approx(float(shot.get(&"speed")), 315.0), "M01 did not gain 75% speed after wall contact")
	check(visual.texture.resource_path.contains("impact_updown"), "M01 did not display its impact frame")
	check(shot.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "M01 retained interpolation ghosting")
	check(world.get_node_or_null("SlimeImpact") == null, "M01 created a duplicate impact sprite")
	shot.call(&"_ricochet_at", wall, shot.global_position, Vector2.LEFT)
	check(bool(shot.get(&"consumed")), "M01 did not expire after its one bounce")
	check(bool(shot.visible) and shot.get(&"phase") == &"impact_ending", "M01 did not finish with its own impact frame")
	shot.free()

	var enemy_shot: Node2D = scene.instantiate() as Node2D
	world.add_child(enemy_shot)
	enemy_shot.set_physics_process(false)
	enemy_shot.position = Vector2.ZERO
	enemy_shot.call(&"configure", &"M01", Vector2.RIGHT, _make_attack(), effects)
	enemy_shot.call(&"_physics_process", 0.09)
	check(is_equal_approx(enemy.health, 97.0), "enemy contact did not damage")
	check((enemy_shot.get(&"direction") as Vector2).x < 0.0, "enemy normal did not reflect")
	enemy_shot.call(&"_ricochet_at", enemy, enemy.position, Vector2.RIGHT)
	check(is_equal_approx(enemy.health, 94.0), "recontact did not apply secondary damage")
	enemy_shot.free()

	var custom_shot: Node2D = scene.instantiate() as Node2D
	world.add_child(custom_shot)
	custom_shot.set_physics_process(false)
	custom_shot.set(&"max_ricochets", 4)
	custom_shot.call(&"configure", &"M01", Vector2.RIGHT, _make_attack(), effects)
	check(int(custom_shot.get(&"remaining_ricochets")) == 4, "exported bounce budget ignored")
	for index: int in range(5):
		custom_shot.call(&"_ricochet_at", wall, Vector2.ZERO, Vector2.LEFT)
		check(bool(custom_shot.get(&"consumed")) == (index == 4), "custom budget ended at wrong contact")
	custom_shot.free()

	var nearby: DummyEnemy = DummyEnemy.new()
	nearby.collision_layer = 4
	nearby.position = Vector2(27.0, 0.0)
	world.add_child(nearby)
	nearby.add_to_group(&"enemy_bodies")
	var heavy: Node2D = scene.instantiate() as Node2D
	world.add_child(heavy)
	heavy.set_physics_process(false)
	heavy.position = Vector2.ZERO
	heavy.call(&"configure", &"M02", Vector2.RIGHT, _make_attack(7.5, 145.0), effects)
	heavy.call(&"_physics_process", 0.09)
	check(bool(heavy.get(&"consumed")) and heavy.get(&"phase") == &"impact_ending", "M02 ricocheted instead of exploding")
	check(is_equal_approx(enemy.health, 86.5), "M02 direct blast damage was not 2.5x M01")
	check(is_equal_approx(nearby.health, 92.5), "M02 blast missed nearby enemy")
	check(is_equal_approx(enemy.last_impulse, 145.0) and is_equal_approx(nearby.last_impulse, 145.0), "M02 blast did not knock both enemies back")
	check(nearby.last_direction.x > 0.0, "M02 knockback did not push outward")
	check((heavy.get_node("Visual") as Sprite2D).scale.x > 1.1875, "M02 blast has no visual expansion")
	heavy.free()
	print("SLIME RICOCHET REGRESSION: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
