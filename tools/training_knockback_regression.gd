extends SceneTree
## M02 must physically displace the infinite-health Minotaur in the preview room.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/dungeon/merchant_platform.tscn")
	await create_timer(0.6).timeout
	var room: Node2D = current_scene as Node2D
	var target: Minotaur = room.get_node("TrainingMinotaur") as Minotaur
	var effects: CombatEffects = room.get_node("ManifestationController/AspectEffects") as CombatEffects
	var origin: Vector2 = target.global_position
	_check(target.training_dummy and target.is_physics_processing(), "Training Minotaur cannot react to physics impulse")
	target.resistance = 100.0
	var card: ManifestationCard = load("res://resources/cards/preview/M02.tres") as ManifestationCard
	var attack: CardAttack = CardAttack.new()
	attack.damage = card.damage
	attack.impact_impulse = card.impact_impulse
	attack.projectile_speed = card.projectile_speed
	attack.projectile_lifetime = card.projectile_lifetime
	var scene: PackedScene = load("res://scenes/dungeon/manifestation_projectile.tscn") as PackedScene
	var shot: Node2D = scene.instantiate() as Node2D
	room.add_child(shot)
	shot.set_physics_process(false)
	shot.call(&"configure", &"M02", Vector2.RIGHT, attack, effects)
	shot.call(&"_explode_m02", target, origin - Vector2(5.0, 0.0), Vector2.LEFT)
	_check(target.hit_velocity.x > 0.0, "M02 explosion did not impart forward knockback")
	_check(is_equal_approx(target.resistance, 92.5), "Training Minotaur did not receive the exact 7.5 M02 damage")
	for index: int in range(8):
		await physics_frame
	_check(target.global_position.x > origin.x + 3.0, "Training Minotaur did not move backward after M02 explosion")
	await create_timer(1.0).timeout
	_check(target.global_position.distance_to(origin) < 3.0, "Training Minotaur failed to settle back near its station")
	print("TRAINING KNOCKBACK: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
