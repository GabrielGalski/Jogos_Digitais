extends SceneTree
## M07 five-frame projectile and M08 persistent fire stream share CardAttack.

class DummyEnemy extends StaticBody2D:
	var health: float = 100.0
	func is_alive() -> bool:
		return health > 0.0
	func take_damage(amount: float) -> void:
		health -= amount

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _aim_right() -> Vector2:
	return Vector2(100.0, 0.0)


func _runtime_for(code: String) -> CardCombatRuntime:
	var loadout: CardLoadout = CardLoadout.new()
	loadout.manifestation = load("res://resources/cards/preview/" + code + ".tres") as ManifestationCard
	var cards: CardCombatRuntime = CardCombatRuntime.new()
	check(cards.equip(loadout), code + " card rejected by runtime")
	return cards


func _run() -> void:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	var effects: CombatEffects = CombatEffects.new()
	effects.camera_feedback_enabled = false
	world.add_child(effects)
	var enemy: DummyEnemy = DummyEnemy.new()
	enemy.collision_layer = 4
	enemy.position = Vector2(30.0, 0.0)
	var enemy_shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 5.0
	enemy_shape.shape = circle
	enemy.add_child(enemy_shape)
	world.add_child(enemy)
	enemy.add_to_group(&"enemy_bodies")
	await physics_frame

	var m07: CardCombatRuntime = _runtime_for("M07")
	var fire_attack: CardAttack = m07.create_attack()
	check(is_equal_approx(fire_attack.fire_interval, 0.25), "M07 reload differs from five frames at 20 fps")
	check(is_equal_approx(fire_attack.projectile_lifetime, fire_attack.fire_interval), "M07 lifetime differs from reload")
	var projectile_scene: PackedScene = load("res://scenes/dungeon/manifestation_projectile.tscn") as PackedScene
	var shot: Node2D = projectile_scene.instantiate() as Node2D
	world.add_child(shot)
	shot.set_physics_process(false)
	shot.call(&"configure", &"M07", Vector2.RIGHT, fire_attack, effects)
	check((shot.get_node("Visual") as Sprite2D).texture.resource_path.ends_with("flame1.png"), "M07 first frame missing")
	shot.call(&"_physics_process", 0.10)
	check(is_equal_approx(enemy.health, 96.0), "M07 did not hit the first enemy")
	check(bool(shot.get("consumed")), "M07 did not end after enemy impact")
	shot.free()

	var wall: StaticBody2D = StaticBody2D.new()
	wall.position = Vector2(12.0, 0.0)
	var wall_shape: CollisionShape2D = CollisionShape2D.new()
	var wall_box: RectangleShape2D = RectangleShape2D.new()
	wall_box.size = Vector2(4.0, 40.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	world.add_child(wall)
	await physics_frame
	var blocked: Node2D = projectile_scene.instantiate() as Node2D
	world.add_child(blocked)
	blocked.set_physics_process(false)
	blocked.call(&"configure", &"M07", Vector2.RIGHT, m07.create_attack(), effects)
	blocked.call(&"_physics_process", 0.10)
	check(bool(blocked.get("consumed")) and is_equal_approx(enemy.health, 96.0), "M07 crossed a solid barrier")
	blocked.free()
	wall.free()
	await physics_frame

	var animated: Node2D = projectile_scene.instantiate() as Node2D
	world.add_child(animated)
	animated.set_physics_process(false)
	animated.position = Vector2(0.0, 60.0)
	animated.call(&"configure", &"M07", Vector2.RIGHT, m07.create_attack(), effects)
	var seen: Dictionary = {}
	seen[(animated.get_node("Visual") as Sprite2D).texture.resource_path] = true
	for index: int in range(4):
		animated.call(&"_physics_process", 0.05)
		seen[(animated.get_node("Visual") as Sprite2D).texture.resource_path] = true
	check(seen.size() == 5, "M07 did not show all five flame frames")
	animated.call(&"_physics_process", 0.05)
	check(animated.is_queued_for_deletion(), "M07 continued beyond its animation")
	animated.free()

	enemy.position = Vector2(60.0, 0.0)
	enemy.health = 100.0
	var source: Marker2D = Marker2D.new()
	world.add_child(source)
	var stream_script: Script = load("res://scripts/dungeon/efreeti_flamethrower.gd") as Script
	var stream: Node2D = stream_script.new() as Node2D
	world.add_child(stream)
	var m08: CardCombatRuntime = _runtime_for("M08")
	stream.call(&"setup", source, Callable(self, "_aim_right"), m08.create_attack())
	var jet: CPUParticles2D = stream.get_node("Jet") as CPUParticles2D
	check(jet.emitting and (stream.get_node("EdgeSparks") as CPUParticles2D).emitting, "M08 emitters did not start")
	check(not bool(stream.call(&"contains_target", Vector2(60, 0))), "M08 reached distant target before growing")
	check(bool(stream.call(&"contains_target", Vector2(-10, 3))), "M08 lost its close contact region")
	stream.set("firing_age", 0.25)
	check(bool(stream.call(&"contains_target", enemy.position)), "M08 did not grow to its target")
	check(not bool(stream.call(&"contains_target", Vector2(180, 0))), "M08 range is too long")
	check(not bool(stream.call(&"contains_target", Vector2(60, 48))), "M08 cone is too wide")
	var palette: Array[Color] = [Color("#fffc40"), Color("#ffd541"), Color("#fa6a0a"), Color("#df3e23")]
	var stops: Array[float] = [0.0, 0.24, 0.58, 0.82]
	for index: int in range(palette.size()):
		check(jet.color_ramp.sample(stops[index]).is_equal_approx(palette[index]), "M08 palette stop " + str(index))
	var first_tick: CardAttack = m08.create_attack()
	check(bool(stream.call(&"apply_channel_hit", first_tick, effects)), "M08 missed target inside stream")
	check(is_equal_approx(enemy.health, 96.0), "M08 damage did not come from its card")
	stream.call(&"apply_channel_hit", first_tick, effects)
	check(is_equal_approx(enemy.health, 96.0), "M08 repeated one CardAttack on the same target")
	stream.call(&"apply_channel_hit", m08.create_attack(), effects)
	check(is_equal_approx(enemy.health, 92.0), "M08 second card tick did not damage")
	stream.call(&"stop_firing")
	check(not jet.emitting and not bool(stream.call(&"apply_channel_hit", m08.create_attack(), effects)), "M08 kept firing after release")
	stream.call(&"_physics_process", 0.47)
	check(stream.is_queued_for_deletion(), "M08 tail did not dissipate")
	world.free()

	root.size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/dungeon/merchant_platform.tscn")
	await create_timer(0.5).timeout
	var room: Node2D = current_scene as Node2D
	var controller: Node = room.get_node("ManifestationController")
	controller.set_physics_process(false)
	var reticle: Node2D = room.get_node("CombatUI/Crosshair") as Node2D
	reticle.position = room.get_viewport().get_canvas_transform() * Vector2(100.0, -32.0)
	controller.set("selected_index", 6)
	controller.call(&"_equip_selected")
	controller.call(&"_fire")
	var shots: Node2D = room.get_node("ManifestationProjectiles") as Node2D
	check(shots.get_child_count() == 1 and shots.get_child(0).get("mode") == &"M07", "M07 not wired into scene cycling")
	controller.set("selected_index", 7)
	controller.call(&"_equip_selected")
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = reticle.position
	Input.parse_input_event(press)
	await process_frame
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "headless input did not register held fire")
	controller.call(&"_update_flamethrower", 0.016)
	var active: Node2D = controller.get("flame_stream") as Node2D
	check(is_instance_valid(active) and bool(active.get("firing")), "M08 not wired into scene cycling")
	if is_instance_valid(active):
		controller.call(&"_update_flamethrower", 0.016)
		check(controller.get("flame_stream") == active, "holding M08 created a second emitter")
		var release: InputEventMouseButton = press.duplicate() as InputEventMouseButton
		release.pressed = false
		Input.parse_input_event(release)
		await process_frame
		controller.call(&"_update_flamethrower", 0.016)
		check(not bool(active.get("firing")), "M08 scene stream did not stop on release")
	print("EFREETI MANIFESTATIONS REGRESSION: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
