extends SceneTree
## Rendered review in the production map: palettes, live movement/shooting and corpses.
const WORLD: PackedScene = preload("res://scenes/maps/open_world.tscn")
const PACK: Script = preload("res://scripts/enemies/insects/insect_pack.gd")
const PALETTES: Script = preload("res://scripts/visual/insect_palettes.gd")
const OUT: String = "res://output/insect_refinement/"
var arena: Node2D = null
var player: Player = null
var zones: Node2D = null
var review_pack: Node2D = null
var failures: Array[String] = []
var report: Dictionary = {}
var shots: int = 0
var deaths: int = 0
var _held_key: Key = KEY_NONE


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if value: return
	failures.append(message)
	push_error("[INSECT_REVIEW] " + message)


func frames(count: int) -> void:
	for index: int in range(count): await physics_frame


func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "Capture " + label)


func clear_patch() -> Vector2:
	var origin: Vector2 = player.global_position + Vector2(0, 96)
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 12.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	for radius: int in range(0, 10):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius: continue
				var center: Vector2 = origin + Vector2(x, y) * 16.0
				var height: float = float(arena.get_node("TerrainElevation").call("height_at", center))
				var valid: bool = true
				for offset: Vector2 in [Vector2(-48, -20), Vector2(0, -20), Vector2(48, -20), Vector2(0, 32), Vector2(-48, 32), Vector2(48, 32)]:
					var point: Vector2 = center + offset
					if not bool(arena.call("is_ground_surface_point", point)): valid = false
					if absf(float(arena.get_node("TerrainElevation").call("height_at", point)) - height) > 1.0: valid = false
					query.transform = Transform2D(0.0, point)
					if not arena.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): valid = false
				if valid: return center
	check(false, "An open patch exists near the normal world entrance")
	return player.global_position


func key_event(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func hold_key(code: Key) -> void:
	if _held_key == code: return
	if _held_key != KEY_NONE: key_event(_held_key, false)
	_held_key = code
	if code != KEY_NONE: key_event(code, true)


func trigger(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.size * 0.5
	Input.parse_input_event(event)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.title = "Monster Booster - Insect Review"
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(480, 270)
	arena = WORLD.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	zones = arena.get_node("InsectZones") as Node2D
	var deadline: int = Time.get_ticks_msec() + 8000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline: await process_frame
	check(bool(arena.get("entry_complete")), "Production world entrance completes")
	await frames(90)
	check(int(zones.call("live_count")) > 0 and get_nodes_in_group(&"flying_eyes").is_empty(), "Normal map spawns insects and no Flying Eyes")
	await capture("normal_entry")
	var center: Vector2 = clear_patch()
	player.position = center + Vector2(0, 32)
	player.snap_floor_height()
	player.reset_physics_interpolation()
	player.set_physics_process(false)
	var shooter: Node2D = player.get_node("BoosterShooter") as Node2D
	shooter.set_process(false)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.35
	camera.force_update_scroll()
	review_pack = PACK.new() as Node2D
	arena.add_child(review_pack)
	var starts: Array[Vector2] = [center + Vector2(-48, -20), center + Vector2(0, -20), center + Vector2(48, -20)]
	var kinds: Array[StringName] = [&"tall", &"fly", &"little"]
	review_pack.call("configure", center, starts, kinds, player, Callable(arena, "is_ground_surface_point"), Callable(arena, "_terrain_and_warp_height"), 280.0, 192.0, 0.8, arena.get_node("EnemyRemains"))
	review_pack.set_physics_process(false)
	var actors: Array[InsectActor] = review_pack.get("members") as Array[InsectActor]
	for actor: InsectActor in actors:
		actor.set_physics_process(false)
		actor.visual.play(&"idle")
		actor.visual.set_frame_and_progress(0, 0.0)
		actor.visual.pause()
	var legend: CanvasLayer = CanvasLayer.new()
	legend.layer = 95
	root.add_child(legend)
	var title: Label = Label.new()
	title.position = Vector2(10, 222)
	title.add_theme_font_size_override("font_size", 12)
	legend.add_child(title)
	for variant: int in range(3):
		zones.call("set_palette_variant", variant)
		for actor: InsectActor in actors: actor.visual.call("set_palette_variant", variant)
		title.text = "%d/3 - %s\nTall | Fly | Little" % [variant + 1, PALETTES.LABELS[variant]]
		await frames(3)
		for actor: InsectActor in actors:
			var used: Rect2i = actor.visual.sprite_frames.get_frame_texture(&"idle", 0).get_image().get_used_rect()
			var rect: Rect2 = Rect2(Vector2(used.position) - Vector2(24, 24) + actor.visual.offset, Vector2(used.size))
			var transform: Transform2D = actor.visual.get_global_transform_with_canvas()
			check(root.get_visible_rect().has_point(transform * rect.position) and root.get_visible_rect().has_point(transform * rect.end), "Palette capture frames the complete " + str(actor.profile.kind))
		await capture("palette_%d" % (variant + 1))
	legend.queue_free()
	zones.call("set_palette_variant", 0)
	for actor: InsectActor in actors:
		actor.visual.call("set_palette_variant", 0)
		actor.set_physics_process(true)
		actor.died.connect(func(_actor: Node2D) -> void: deaths += 1)
	review_pack.set_physics_process(true)
	player.set_physics_process(true)
	player.contact_invulnerability = 1000.0
	shooter.set_process(true)
	shooter.connect("shot_fired", func() -> void: shots += 1)
	var started: int = Time.get_ticks_usec()
	var previous: int = started
	var previous_position: Vector2 = player.global_position
	var traveled: float = 0.0
	var durations: Array[float] = []
	var shooting: bool = false
	var captured_fight: bool = false
	while Time.get_ticks_usec() - started < 12000000:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var elapsed: float = (now - started) / 1000000.0
		durations.append((now - previous) / 1000.0)
		previous = now
		traveled += player.global_position.distance_to(previous_position)
		previous_position = player.global_position
		var keys: Array[Key] = [KEY_D, KEY_W, KEY_A, KEY_S]
		hold_key(keys[int(elapsed / 0.42) % 4])
		if elapsed > 4.0 and not shooting:
			shooting = true
			trigger(true)
		var target: InsectActor = null
		if is_instance_valid(review_pack):
			for candidate: InsectActor in review_pack.get("members") as Array:
				if target == null or candidate.player_distance() < target.player_distance(): target = candidate
		if target != null:
			shooter.set("aim_screen_override", arena.get_viewport().get_canvas_transform() * (target.global_position + Vector2(0, -8 - target.floor_height)))
		if elapsed > 6.0 and not captured_fight:
			captured_fight = true
			await capture("live_combat")
	hold_key(KEY_NONE)
	trigger(false)
	durations.sort()
	report["live"] = {"seconds": (Time.get_ticks_usec() - started) / 1000000.0, "traveled_px": traveled, "shots": shots, "projectile_kills": deaths, "frame_p50_ms": durations[int(durations.size() * 0.5)], "frame_p95_ms": durations[int(durations.size() * 0.95)], "frame_max_ms": durations[-1]}
	check(traveled > 300.0 and shots > 5, "Rendered game exercises real walking and firing")
	check(deaths > 0, "Real projectiles kill the reviewed insects")
	shooter.set_process(false)
	player.set_physics_process(false)
	if is_instance_valid(review_pack):
		for actor: InsectActor in (review_pack.get("members") as Array).duplicate(): actor.take_damage(999.0)
	await frames(60)
	check(int(arena.get_node("EnemyRemains").call("total_count")) >= 3, "Production deaths leave scene-owned final frames")
	await capture("death_remains")
	report["failures"] = failures
	var output: FileAccess = FileAccess.open(OUT + "visual_review.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("INSECT_VISUAL_REVIEW ", "PASS" if failures.is_empty() else "FAIL", " ", JSON.stringify(report))
	await create_timer(4.0).timeout
	quit(0 if failures.is_empty() else 1)
