extends Node
const ARENA: PackedScene = preload("res://scenes/tutorial_arena.tscn")
var failures: int = 0
var arena: Node2D
var boss: Variant
var player: CharacterBody2D
var actor: CharacterBody2D
var sensor: EnemyAIWorldSensor2D
var ai: AsterionAI

func _ready() -> void:
	arena = ARENA.instantiate() as Node2D
	boss = arena.get_node("MinotaurChair")
	boss.auto_start_encounter = false
	add_child(arena)
	boss.set_physics_process(false)
	for tween: Tween in get_tree().get_processed_tweens():
		tween.kill()
	player = arena.get_node("Mox") as CharacterBody2D
	player.set_physics_process(false)
	actor = boss.actor
	sensor = boss.ai_world_sensor
	ai = boss.ai
	await get_tree().physics_frame
	actor.get_node("BodyCollision").disabled = false
	await get_tree().physics_frame
	await traverse("small_vertical", Vector2(152, -65), Vector2(152, 87))
	await traverse("small_horizontal", Vector2(70, 8), Vector2(228, 8))
	await traverse("large_vertical", Vector2(-180, -185), Vector2(-180, 35))
	await traverse("large_horizontal", Vector2(-288, -76), Vector2(-60.0, -76))
	await traverse("throne_back", Vector2(-85, -238), Vector2(85, -238))
	await traverse("arena_diagonal", Vector2(-286, 165), Vector2(283, -275))
	await traverse("moving_target", Vector2(-270, -185), Vector2(-75, 25), true)
	await unreachable()
	await crowd()
	await load_test()
	await combat_cycle()
	poses()
	print("[NAV SUMMARY] failures=%s build_ms=%.2f builds=%s replans=%s queries=%s" % [
		failures, sensor.navigation.build_usec / 1000.0, sensor.navigation.builds, sensor.replans, sensor.navigation.path_queries])
	get_tree().quit(1 if failures else 0)

func setup(start: Vector2, target: Vector2) -> void:
	player.global_position = target
	actor.global_position = start
	actor.velocity = Vector2.ZERO
	ai.attack_cooldown_remaining = 0.0
	ai.special_cooldown_remaining = 9999.0
	boss._enter_chase()
	boss.body_shape.disabled = false

func traverse(label: String, start: Vector2, target: Vector2, moving: bool = false) -> void:
	setup(start, target)
	await get_tree().physics_frame
	var reached: bool = false
	var traveled: float = 0.0
	var last: Vector2 = actor.global_position
	var max_stall: int = 0
	var stall: int = 0
	var replan_start: int = sensor.replans
	var started: int = Time.get_ticks_usec()
	var ticks: int = 0
	for tick: int in range(2400):
		ticks = tick
		if moving and tick == 180:
			player.global_position += Vector2(120, 45)
		boss._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
		var distance: float = actor.global_position.distance_to(last)
		traveled += distance
		stall = stall + 1 if distance < 0.01 else 0
		max_stall = maxi(max_stall, stall)
		last = actor.global_position
		if boss.state == boss.State.MELEE_PREPARE:
			reached = true
			break
		if boss.state == boss.State.SKYBREAKER_PREPARE:
			check(false, label + ": navigation escaped using a jump")
			break
	check(reached, label + ": must reach melee range without jumping; end=" + str(actor.global_position))
	check(max_stall < 120, label + ": stalled for two seconds")
	print("[NAV CASE] %s reached=%s seconds=%.2f traveled=%.1f max_stall=%.2f replans=%s cpu_ms=%.2f" % [
		label, reached, ticks / 60.0, traveled, max_stall / 60.0, sensor.replans - replan_start, (Time.get_ticks_usec() - started) / 1000.0])

func unreachable() -> void:
	var wall: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(800, 16)
	shape.shape = rectangle
	wall.add_child(shape)
	arena.add_child(wall)
	wall.position = Vector2(0, 110)
	await get_tree().physics_frame
	sensor.navigation.invalidate()
	setup(Vector2(0, 170), Vector2(0, 60))
	var start: Vector2 = actor.global_position
	for tick: int in range(90):
		boss._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
	check(actor.global_position.distance_to(start) < 1.0, "Disconnected areas must hold, not guess a route")
	wall.queue_free()
	await get_tree().physics_frame
	sensor.navigation.invalidate()
	await traverse("opened_passage", Vector2(0, 170), Vector2(0, 60))

func crowd() -> void:
	var bodies: Array[CharacterBody2D] = []
	setup(Vector2(-65, 105), Vector2(75, 105))
	await get_tree().physics_frame
	var shared: EnemyAIWorldSensor2D = EnemyAIWorldSensor2D.new()
	add_child(shared)
	shared.configure(arena, sensor.navigation.bounds)
	shared.build_observation(actor, player, EnemyAIEnums.Objective.PRESSURE_TARGET, 32, false)
	check(shared.navigation == sensor.navigation, "Actors share the same clearance map")
	for i: int in range(32):
		var body: CharacterBody2D = CharacterBody2D.new()
		var collision: CollisionShape2D = CollisionShape2D.new()
		collision.name = "BodyCollision"
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 5.0
		collision.shape = circle
		body.add_child(collision)
		arena.add_child(body)
		body.add_to_group(&"enemy_ai_actor")
		body.global_position = Vector2(-20 + (i % 4) * 12, 70 + floori(float(i) / 4.0) * 12)
		bodies.append(body)
	await get_tree().physics_frame
	await traverse("crowd_bypass", Vector2(-65, 105), Vector2(75, 105))
	for body: CharacterBody2D in bodies:
		body.queue_free()
	shared.queue_free()
	await get_tree().physics_frame

func load_test() -> void:
	# 48 brains request and follow independent routes; the chamber map is reused.
	var sensors: Array[EnemyAIWorldSensor2D] = []
	var bodies: Array[CharacterBody2D] = []
	var targets: Array[CharacterBody2D] = []
	for i: int in range(48):
		var body: CharacterBody2D = CharacterBody2D.new()
		var target: CharacterBody2D = CharacterBody2D.new()
		arena.add_child(body)
		arena.add_child(target)
		body.global_position = Vector2(-290.0 + float(i % 6) * 12.0, 100.0 + floorf(float(i) / 6.0) * 12.0)
		target.global_position = Vector2(250.0, -200.0)
		var local_sensor: EnemyAIWorldSensor2D = EnemyAIWorldSensor2D.new()
		add_child(local_sensor)
		local_sensor.configure(arena, sensor.navigation.bounds)
		sensors.append(local_sensor)
		bodies.append(body)
		targets.append(target)
	await get_tree().physics_frame
	var samples: Array[int] = []
	for tick: int in range(180):
		var started: int = Time.get_ticks_usec()
		for i: int in range(sensors.size()):
			var observation: EnemyAIObservation = sensors[i].build_observation(bodies[i], targets[i], EnemyAIEnums.Objective.PRESSURE_TARGET, 28.0, false, 0.12)
			bodies[i].position += observation.route_direction * 44.0 * 0.12
		samples.append(Time.get_ticks_usec() - started)
	var shared_grid: EnemyNavigationGrid = sensors[0].navigation
	for local_sensor: EnemyAIWorldSensor2D in sensors:
		check(local_sensor.navigation == shared_grid, "48 actors share one map per radius")
	check(shared_grid.builds == 1, "The stress group builds its map only once")
	samples.sort()
	print("[NAV LOAD] 48 sensors, 180 sensing rounds (no crowd physics): median_ms=%.3f p95_ms=%.3f build_ms=%.3f" % [
		samples[90] / 1000.0, samples[171] / 1000.0, shared_grid.build_usec / 1000.0])
	for i: int in range(sensors.size()):
		sensors[i].queue_free()
		bodies[i].queue_free()
		targets[i].queue_free()
	await get_tree().physics_frame

func combat_cycle() -> void:
	setup(Vector2(0, 30), Vector2(0, 195))
	ai.special_cooldown_remaining = 0.0
	await get_tree().physics_frame
	boss._physics_process(1.0 / 60.0)
	check(boss.state == boss.State.SKYBREAKER_PREPARE, "Distant target triggers field Skybreaker")
	var landed: bool = false
	for tick: int in range(300):
		boss._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
		if boss.state == boss.State.CHASE:
			landed = true
			break
	check(landed, "Field Skybreaker completes and resumes AI")
	check(boss.visual.visible and not boss.field_skybreaker_visual.visible, "Walk sprite replaces airborne sprite")
	setup(Vector2(0, 170), Vector2(0, 195))
	await get_tree().physics_frame
	boss._physics_process(1.0 / 60.0)
	check(boss.state == boss.State.MELEE_PREPARE, "Close target triggers melee")
	for tick: int in range(85):
		boss._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
	check(boss.state == boss.State.CHASE, "Melee completes and returns to AI")

func poses() -> void:
	boss._start_from_throne()
	check(boss.get_node("Asterion").visible and not actor.visible, "Preparation stays on the throne sprite")
	check(boss.get_node("Asterion").animation == &"standing", "Standing frame uses throne transform")
	boss._finish_throne_standing()
	check(boss.get_node("Asterion").animation == &"propulsion" and not actor.visible, "Propulsion stays on throne")
	boss._finish_throne_propulsion()
	check(not boss.get_node("Asterion").visible and actor.visible, "Only one body is visible at takeoff")
	var animated: AnimatedSprite2D = boss.get_node("Asterion") as AnimatedSprite2D
	var throne_top: Vector2 = animated.global_position - animated.sprite_frames.get_frame_texture(&"standing", 0).get_size() * animated.global_scale * 0.5
	var launch_top: Vector2 = boss.visual.global_position + boss.visual.offset * boss.visual.global_scale
	check(throne_top.distance_to(launch_top) < 0.01, "Identical canvas origin before and after transfer")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
