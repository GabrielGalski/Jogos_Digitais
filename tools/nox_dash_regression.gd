extends SceneTree

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
var failures: PackedStringArray = PackedStringArray()
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var arena: Node2D = Node2D.new()
	root.add_child(arena)
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1.0, 1.0).normalized()]
	var player: Player
	var line: Node2D
	for direction: Vector2 in directions:
		player = PLAYER_SCENE.instantiate() as Player
		player.movement_bounds = Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
		arena.add_child(player)
		line = player.get_node("MomentumLine") as Node2D
		await process_frame
		_check(is_equal_approx(player.dash_speed, 495.0), "Dash speed is 50% higher")
		_check(is_equal_approx(player.dash_speed * player.dash_duration, 105.6), "Nominal range is doubled")
		_check(player.dash_charges == 2 and is_equal_approx(player.dash_cooldown, 0.5), "Two charges start full, with 0.5 s recharge")
		var tint: Color = line.get(&"tint")
		_check(tint.to_html(false) == "4c2f49", "Momentum stroke uses the requested color")
		var start_position: Vector2 = player.global_position
		_check(player.try_dash(direction), "Dash starts in each direction")
		_check(player.dash_charges == 1, "One dash spends exactly one charge")
		_check(not player.try_dash(direction), "Dashes cannot overlap")
		var peak: float = 0.0
		var saw_visible: bool = false
		var saw_hidden_after_visible: bool = false
		var frames: int = 0
		while player.is_dashing() and frames < 40:
			await physics_frame
			await process_frame
			frames += 1
			peak = maxf(peak, float(line.get(&"strength")))
			if line.visible:
				saw_visible = true
			elif saw_visible:
				saw_hidden_after_visible = true
		_check(absf(player.global_position.distance_to(start_position) - 105.6) < 0.15, "Measured range is 105.6 px, including diagonals")
		_check(peak > 0.25 and saw_visible, "Fast travel reveals the momentum stroke")
		_check(saw_hidden_after_visible, "Stroke disappears between pulses while moving")
		var actual_direction: Vector2 = line.get(&"motion_direction")
		_check(actual_direction.dot(direction) > 0.99, "Stroke follows actual movement direction")
		var expected_head: Vector2 = line.to_local(player.body.to_global(player.body.offset + Vector2(0.0, -21.0)))
		var actual_head: Vector2 = line.get(&"head_anchor")
		_check(actual_head.distance_to(expected_head) < 1.6, "Stroke stays at the scaled, tilted head")
		await create_timer(0.24).timeout
		_check(not line.visible and float(line.get(&"strength")) < 0.02, "Stroke fades away at rest")
		if direction != directions.back():
			player.queue_free()
			await process_frame

	_key(KEY_D, true)
	await create_timer(0.1).timeout
	_key(KEY_D, false)
	_check(not line.visible and is_zero_approx(float(line.get(&"target_strength"))), "Normal walking does not show speed strokes")
	player.position += Vector2(300.0, 0.0)
	await physics_frame
	await physics_frame
	await process_frame
	_check(not line.visible and is_zero_approx(float(line.get(&"strength"))), "Teleport cannot produce a speed stroke")
	player.dash_recovery = 0.0
	player.try_dash(Vector2.RIGHT)
	await physics_frame
	await physics_frame
	player.intro_locked = true
	await physics_frame
	await physics_frame
	await process_frame
	_check(not player.is_dashing() and not line.visible, "Control lock cancels dash and clears the stroke")
	player.queue_free()
	await process_frame

	# Deterministic clock checks isolate the charge model from frame timing.
	player = PLAYER_SCENE.instantiate() as Player
	arena.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.try_dash(Vector2.RIGHT)
	player.dash_remaining = 0.0
	player._recover_dash_charges(player.dash_duration)
	var first_clock: float = player.dash_recovery
	_check(player.try_dash(Vector2.LEFT), "Second dash starts immediately after the first ends")
	_check(player.dash_charges == 0 and is_equal_approx(player.dash_recovery, first_clock), "Second charge keeps the first recharge clock")
	player.dash_remaining = 0.0
	_check(not player.try_dash(Vector2.RIGHT), "A third dash waits for a new charge")
	player._recover_dash_charges(first_clock - 0.01)
	_check(player.dash_charges == 0, "No charge reappears before 0.5 s")
	player._recover_dash_charges(0.02)
	_check(player.dash_charges == 1, "First charge returns after 0.5 s")
	player._recover_dash_charges(0.48)
	_check(player.dash_charges == 1, "Second charge needs its own recharge interval")
	player._recover_dash_charges(0.02)
	_check(player.dash_charges == 2 and is_zero_approx(player.dash_recovery), "Both charges return after their sequential intervals")
	player.dash_charges = 0
	player.dash_recovery = 0.5
	player._recover_dash_charges(1.2)
	_check(player.dash_charges == 2, "A slow frame recovers every elapsed interval, capped at two charges")
	player.queue_free()
	await process_frame

	var wall: StaticBody2D = StaticBody2D.new()
	wall.position = Vector2(40.0, 0.0)
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(2.0, 48.0)
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = rectangle
	wall.add_child(collider)
	arena.add_child(wall)
	player = PLAYER_SCENE.instantiate() as Player
	arena.add_child(player)
	await physics_frame
	await physics_frame
	player.try_dash(Vector2.RIGHT)
	await create_timer(0.3).timeout
	_check(player.position.x < 39.0 and not player.is_dashing(), "Faster dash still stops at solid walls")
	var report: Dictionary = {"passed": failures.is_empty(), "checks": checks, "failures": Array(failures)}
	var report_file: FileAccess = FileAccess.open("res://tmp/nox_dash_regression.json", FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report))
		report_file.close()
	print(JSON.stringify(report))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
