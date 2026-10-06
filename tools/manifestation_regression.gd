extends SceneTree
## Regression: shared aspects, projectile visuals, proximity burst and dash ghosts.
class DummyEnemy extends Node2D:
	var health: float = 100.0
	var last_hit_direction: Vector2 = Vector2.RIGHT
	func is_alive() -> bool:
		return health > 0.0
	func take_damage(amount: float) -> void:
		health = maxf(0.0, health - amount)

class CountingEffects extends CombatEffects:
	var bursts: int = 0
	func _spawn_explosion_visual(_center: Vector2, _radius: float) -> void:
		bursts += 1

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var effects: CountingEffects = CountingEffects.new()
	effects.camera_feedback_enabled = false
	root.add_child(effects)
	var enemy: DummyEnemy = DummyEnemy.new()
	root.add_child(enemy)
	enemy.add_to_group(&"enemy_bodies")
	var other: DummyEnemy = DummyEnemy.new()
	root.add_child(other)
	other.position = Vector2(500, 0)
	other.add_to_group(&"enemy_bodies")
	var loadout: CardLoadout = load("res://resources/cards/starter_loadout.tres").duplicate(true) as CardLoadout
	loadout.mutation = load("res://resources/cards/fury_heart.tres") as MutationCard
	var runtime: CardCombatRuntime = CardCombatRuntime.new()
	check(runtime.equip(loadout), "typed loadout rejected")
	var attack: CardAttack = runtime.create_attack()
	attack.apply_primary_hit(enemy, enemy.position, Vector2.RIGHT, effects)
	attack.apply_primary_hit(enemy, enemy.position, Vector2.RIGHT, effects)
	check(enemy.health == 94.0 and effects.bursts == 1, "duplicate hit or infusion")
	attack.apply_primary_hit(other, other.position, Vector2.RIGHT, effects)
	check(other.health == 97.0 and effects.bursts == 1, "piercing retriggers infusion")
	other.health = 1.0
	attack.apply_secondary_hit(other, 1.0, Vector2.RIGHT, effects)
	check(runtime.movement_multiplier() == 1.2, "secondary kill did not activate mutation")
	check(effects.bursts == 1, "damage over time retriggered infusion")
	runtime.equip(loadout)
	enemy.health = 1.0
	attack.apply_secondary_hit(enemy, 1.0, Vector2.RIGHT, effects)
	check(runtime.movement_multiplier() == 1.0, "old snapshot activated newly equipped mutation")
	runtime.equip(CardLoadout.new())
	check(runtime.create_attack() == null, "empty manifestation still attacks")
	enemy.free()
	other.free()
	effects.free()

	root.size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/dungeon/merchant_platform.tscn")
	await create_timer(0.6).timeout
	var room: Node2D = current_scene as Node2D
	var controller: Node = room.get_node("ManifestationController")
	controller.set_physics_process(false)
	var player: Player = room.get_node("Nox") as Player
	var gun: Node = player.get_node("BoosterShooter")
	check(bool(gun.get("use_card_loadout")), "preview bypasses card runtime")
	var preview_runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var preview_effects: CombatEffects = controller.get("combat_effects") as CombatEffects
	var target: Minotaur = room.get_node("TrainingMinotaur") as Minotaur
	controller.set("selected_index", 2)
	controller.call("_equip_selected")
	var reticle: Node2D = room.get_node("CombatUI/Crosshair") as Node2D
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 10)
	Input.parse_input_event(press)
	await process_frame
	reticle.position = Vector2(10, 10)
	controller.call("_update_laser", 2.0)
	check(is_zero_approx(float(controller.get("laser_tick"))), "laser banks damage while missing")
	reticle.position = room.get_viewport().get_canvas_transform() * target.global_position
	var before: float = float(controller.get("total_damage"))
	controller.call("_update_laser", 1.0 / 60.0)
	var applied: float = float(controller.get("total_damage")) - before
	check(applied > 0.0 and applied <= 6.0, "laser reacquisition damage: " + str(applied))
	var release: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
	var projectile_scene: PackedScene = load("res://scenes/dungeon/manifestation_projectile.tscn") as PackedScene
	for code: String in ["M01", "M02", "M05", "M06"]:
		var selected: CardLoadout = CardLoadout.new()
		selected.manifestation = load("res://resources/cards/preview/" + code + ".tres") as ManifestationCard
		preview_runtime.equip(selected)
		var shot: Node2D = projectile_scene.instantiate() as Node2D
		room.add_child(shot)
		shot.set_physics_process(false)
		shot.position = target.position - Vector2(12, 0)
		shot.call("configure", StringName(code), Vector2.RIGHT, preview_runtime.create_attack(), preview_effects)
		shot.reset_physics_interpolation()
		var visual: Sprite2D = shot.get_node("Visual") as Sprite2D
		if code == "M06":
			check(Vector2.UP.rotated(shot.rotation).dot(Vector2.RIGHT) > 0.99, "spike does not point along travel")
			shot.call("_on_body_entered", target)
			check(shot.get("phase") == &"attached" and visual.visible, "spike not visible while attached")
			check(visual.scale.x < 1.0, "spike too large")
		elif code == "M05":
			check(is_equal_approx(visual.scale.x, 0.45), "mushroom scaling")
			shot.set("phase", &"flying")
			shot.call("_physics_process", 0.016)
			check(shot.get("phase") == &"burst", "mushroom did not explode at proximity")
			check(visual.texture.resource_path.contains("/boom/"), "wrong mushroom explosion frames")
		elif code == "M01":
			var first: Texture2D = visual.texture
			shot.set("animation_clock", 0.06)
			shot.position = Vector2(-100, 0)
			shot.call("_physics_process", 0.016)
			check(visual.texture == first, "rapid slime changes immediately at muzzle")
		elif code == "M02":
			check(is_equal_approx(float(shot.get("speed")), 180.0) and is_equal_approx(visual.scale.x, 1.1875), "heavy slime values")
		shot.free()
	player.try_dash(Vector2.LEFT)
	await physics_frame
	await physics_frame
	check(get_nodes_in_group(&"dash_afterimages").is_empty(), "dash creates ghost silhouettes in test room")
	check(is_equal_approx((room.get_node("Nox/Camera2D") as Camera2D).zoom.x, 0.95), "camera zoom")
	print("MANIFESTATION REGRESSION: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
