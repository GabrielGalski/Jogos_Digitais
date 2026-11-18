extends SceneTree
const SKULL: Script = preload("res://scripts/enemies/flying_skull_pack.gd")
const SLIME: Script = preload("res://scripts/enemies/slime_pack.gd")
const REMAINS: Script = preload("res://scripts/visual/enemy_remains.gd")
const PARRY: Script = preload("res://scripts/combat/player_parry.gd")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const WORLD: PackedScene = preload("res://scenes/maps/open_world.tscn")
const OUT: String = "res://output/biome_enemies/"
var world: Node2D = null
var player: Player = null
var rendered: bool = false
var checks: int = 0
var failures: Array[String] = []
var report: Dictionary = {}
var _shots: int = 0
var _damage_events: int = 0


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("[BIOME] " + message)


func frames(count: int) -> void:
	for index: int in range(count): await physics_frame


func capture(label: String) -> void:
	if not rendered: return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "Capture " + label)


func fixture_pack(script: Script, starts: Array[Vector2]) -> Node2D:
	var pack: Node2D = script.new() as Node2D
	world.add_child(pack)
	pack.call("configure", starts[0], starts, player, FlyingEyeProfile.new(),
		func(_point: Vector2) -> bool: return true, Callable(), 264.0, 192.0, 0.0)
	var neighbors: Array[Node2D] = []
	for actor: Node2D in pack.get("members") as Array: neighbors.append(actor)
	pack.set("neighbors", neighbors)
	return pack


func _assets() -> void:
	var insect_palettes: Script = preload("res://scripts/visual/insect_palettes.gd")
	var monochrome: Dictionary = insect_palettes.PROPOSALS[0] as Dictionary
	check(monochrome[&"tall"] == monochrome[&"fly"] and monochrome[&"fly"] == monochrome[&"little"], "All three insects use the restored monochrome palette by default")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "assets.json")) as Dictionary
	for kind: String in ["flying_skull", "slime"]:
		var settings: Dictionary = manifest[kind] as Dictionary
		check(FileAccess.get_sha256(str(settings.source)) == str(settings.sha256), kind + " source sheet remains intact")
		var clips: SpriteFrames = load("res://resources/enemies/%s/frames.tres" % kind) as SpriteFrames
		var names: Array[StringName] = [&"idle", &"attack", &"hit", &"death"]
		for row: int in range(names.size()):
			check(clips.get_frame_count(names[row]) == int((settings.counts as Array)[row]), "%s %s frame count" % [kind, names[row]])
			var correct: bool = true
			for index: int in range(clips.get_frame_count(names[row])):
				var frame_texture: AtlasTexture = clips.get_frame_texture(names[row], index) as AtlasTexture
				if frame_texture.region != Rect2(index * 32, row * 32, 32, 32): correct = false
			check(correct, "%s %s preserves its source row and fixed pivot" % [kind, names[row]])


func _skulls() -> void:
	var pack: Node2D = fixture_pack(SKULL, [player.position + Vector2(92, -24), player.position + Vector2(80, 50), player.position + Vector2(-88, 20)])
	await frames(330)
	var logs: Array = pack.get("attack_log") as Array
	check(logs.size() >= 6, "Skulls use the original Eye three-orb volleys")
	var ordered: bool = true
	for index: int in range(logs.size()):
		if int(logs[index].shot) != 1 + index % 3: ordered = false
		if index % 3 > 0 and logs[index].actor != logs[index - 1].actor: ordered = false
	check(ordered, "One Skull owns a complete three-shot attack turn")
	check(get_nodes_in_group(&"flying_skulls").size() == 3 and get_nodes_in_group(&"flying_eyes").is_empty(), "Skull variants never reactivate Eye bodies")
	var actor: CharacterBody2D = (pack.get("members") as Array)[0] as CharacterBody2D
	var visual: Sprite2D = actor.get("visual") as Sprite2D
	var colors: PackedColorArray = (visual.material as ShaderMaterial).get_shader_parameter(&"to_colors") as PackedColorArray
	check(colors[0].is_equal_approx(Color("#F1934C")) and colors[1].is_equal_approx(Color("#FEFFE5")) and colors[2].is_equal_approx(Color("#81173F")), "Skull preserves the original sheet colors")
	actor.call("take_damage", 3.0)
	check(is_equal_approx(float(actor.get("health")), 3.0), "Skull retains Eye health and damage reception")
	actor.call("take_damage", 3.0)
	await frames(40)
	check(not is_instance_valid(actor), "The fourth Skull row completes and releases the body")
	report["skull_volleys"] = logs.size()
	pack.call("dismiss")
	await frames(3)


func _slime_cycle() -> void:
	player.health = 60.0
	player.contact_invulnerability = 0.0
	var pack: Node2D = fixture_pack(SLIME, [player.position + Vector2(80, 0)])
	var slime: CharacterBody2D = (pack.get("members") as Array)[0] as CharacterBody2D
	slime.set("_cooldown", 0.0)
	var air_frames_valid: bool = true
	var prelanding_safe: bool = true
	var maximum_height: float = 0.0
	for index: int in range(130):
		await frames(1)
		if int(slime.get("landings")) == 0 and not is_equal_approx(player.health, 60.0): prelanding_safe = false
		if int(slime.get("state")) == 2:
			var pose: int = int(slime.call("attack_frame"))
			if pose < 5 or pose > 7: air_frames_valid = false
			maximum_height = maxf(maximum_height, float(slime.get("jump_height")))
		if int(slime.get("landings")) > 0: break
	check(air_frames_valid and maximum_height > 15.0, "Slime is airborne only on attack sprites 6, 7 and 8")
	check(prelanding_safe and is_equal_approx(player.health, 54.0) and int(slime.get("hits_landed")) == 1, "Landing, rather than windup or flight, deals one medium six-point AoE hit")
	slime.call("resolve_slam")
	check(is_equal_approx(player.health, 54.0), "The same landing cannot damage twice")
	player.contact_invulnerability = 1000.0
	var largest_retreat: float = 0.0
	for index: int in range(300):
		await frames(1)
		if int(slime.get("state")) == 5: largest_retreat = maxf(largest_retreat, slime.global_position.distance_to(player.global_position))
	check(largest_retreat > 45.0 and int(slime.get("jumps_started")) >= 2, "Slime withdraws, creates distance, then approaches for another jump")
	report["slime_cycle"] = {"jump_height": maximum_height, "retreat_distance": largest_retreat, "jumps": slime.get("jumps_started")}
	pack.call("dismiss")
	await frames(3)


func _slam_rules() -> void:
	var manager: Node2D = REMAINS.new() as Node2D
	world.add_child(manager)
	manager.call("configure", func(_point: Vector2) -> bool: return true)
	var pack: Node2D = fixture_pack(SLIME, [player.position + Vector2(24, 0)])
	pack.set_physics_process(false)
	var slime: CharacterBody2D = (pack.get("members") as Array)[0] as CharacterBody2D
	slime.set("remains_system", manager)
	slime.set_physics_process(false)
	player.health = 60.0
	player.contact_invulnerability = 0.0
	slime.call("resolve_slam")
	check(is_equal_approx(player.health, 54.0), "AoE hits a player 24px from the landing, outside contact range")
	slime.position = player.position + Vector2(30, 0)
	slime.set("_slam_consumed", false)
	player.contact_invulnerability = 0.0
	slime.call("resolve_slam")
	check(is_equal_approx(player.health, 54.0), "Stepping beyond the 26px splash radius evades the attack")
	slime.position = player.position + Vector2(20, 0)
	slime.set("_slam_consumed", false)
	player.dash_remaining = 0.2
	slime.call("resolve_slam")
	check(is_equal_approx(player.health, 54.0), "Dash avoids the Slime splash")
	player.dash_remaining = 0.0
	slime.set("_slam_consumed", false)
	slime.set("floor_height", 56.0)
	slime.call("resolve_slam")
	check(is_equal_approx(player.health, 54.0), "Splash cannot hit the player through the castle elevation")
	slime.set("floor_height", 0.0)
	slime.set("_slam_consumed", false)
	check(player.try_parry(), "Existing parry can start against Slime")
	slime.call("resolve_slam")
	check(not bool(slime.call("is_alive")) and is_equal_approx(player.health, 54.0), "Slime landing uses the real parry and reflected damage")
	await frames(40)
	check(not is_instance_valid(slime) and int(manager.call("total_count")) == 1, "Final Slime death pose becomes a cached puddle after releasing its actor")
	manager.call("set_sprite_palette", (preload("res://scripts/visual/insect_palettes.gd") as Script).remains_texture.bind(2))
	check(int(manager.call("total_count")) == 1, "Slime puddles retain their own palette when insect colors change")
	pack.call("dismiss")
	manager.queue_free()
	await frames(3)
	player.parry.call("cancel")


func _find_point(habitats: RefCounted, hint: Vector2, castle: bool) -> Vector2:
	var cells: Dictionary = world.call("_combat_allowed_cells") as Dictionary
	var best: Vector2 = Vector2.ZERO
	var distance: float = INF
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 9.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = 1
	var habitat_points: int = 0
	var blockers: Dictionary = {}
	for cell: Vector2i in cells:
		var point: Vector2 = Vector2(cell * 16) + Vector2.ONE * 8.0
		var candidate_distance: float = point.distance_squared_to(hint)
		if candidate_distance >= distance: continue
		if not bool(habitats.call("is_castle" if castle else "slime_support", point)): continue
		habitat_points += 1
		query.transform = Transform2D(0.0, point)
		var hits: Array[Dictionary] = world.get_world_2d().direct_space_state.intersect_shape(query, 1)
		if not hits.is_empty():
			var collider: Node = hits[0].get("collider") as Node
			var label: String = str(collider.get_path())
			blockers[label] = int(blockers.get(label, 0)) + 1
			continue
		distance = candidate_distance
		best = point
	check(not best.is_zero_approx(), "A traversable habitat point exists")
	if best.is_zero_approx(): print("HABITAT_PROBE ", castle, " cells=", (habitats.get("castle_cells") as Dictionary).size(), " supported=", habitat_points, " blockers=", blockers)
	return best


func _visit(point: Vector2) -> void:
	player.global_position = point
	player.snap_floor_height()
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.35
	camera.reset_smoothing()
	camera.force_update_scroll()
	await frames(110)


func _world() -> void:
	world.queue_free()
	await frames(3)
	world = WORLD.instantiate() as Node2D
	world.set("warp_entry_cutscene_enabled", false)
	root.add_child(world)
	current_scene = world
	player = world.get_node("Nox") as Player
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	var skulls: Node2D = world.get_node("FlyingSkullZones") as Node2D
	var slimes: Node2D = world.get_node("SlimeZones") as Node2D
	var habitats: RefCounted = skulls.get("habitats") as RefCounted
	(skulls.get("_random") as RandomNumberGenerator).seed = 37
	(slimes.get("_random") as RandomNumberGenerator).seed = 19
	await frames(90)
	check(get_nodes_in_group(&"flying_eyes").is_empty() and world.has_node("InsectZones"), "New species preserve insects and keep original Eye spawning disabled")
	var castle_point: Vector2 = _find_point(habitats, Vector2(1600, 600), true)
	await _visit(castle_point)
	var skull_packs: Array = skulls.call("all_packs") as Array
	check(not skull_packs.is_empty() and skull_packs.size() <= 2 and int(skulls.call("live_count")) <= 10, "Castle exploration naturally streams up to two Skull packs")
	var castle_safe: bool = true
	for entry: Dictionary in skulls.get("spawn_log") as Array:
		for point: Vector2 in entry.members as Array:
			var rendered_point: Vector2 = point - Vector2(0, float(world.call("_terrain_and_warp_height", point)) + 8)
			if not bool(habitats.call("is_castle", point)) or (entry.viewport as Rect2).grow(48.0).has_point(rendered_point): castle_safe = false
	check(castle_safe, "Every Skull spawns on actual upper castle tiles, outside the camera")
	if not skull_packs.is_empty():
		await _visit((skull_packs[0].get("anchor") as Vector2) + Vector2(-88, 0))
		await frames(150)
		check(int(skull_packs[0].get("shots_fired")) >= 3, "Production Skull packs emit real Eye projectiles")
		await capture("castle_skulls")
	var river_point: Vector2 = _find_point(habitats, Vector2(2400, 1740), false)
	await _visit(river_point)
	await frames(70)
	var slime_packs: Array = slimes.call("all_packs") as Array
	check(slime_packs.size() >= 3 and slime_packs.size() <= 4 and int(slimes.call("live_count")) <= 20, "River exploration streams more Slimes with a four-pack/20-body ceiling")
	var wet_safe: bool = true
	var water_members: int = 0
	var west_spawns: int = 0
	var east_spawns: int = 0
	for entry: Dictionary in slimes.get("spawn_log") as Array:
		check(int(entry.count) >= 3 and int(entry.count) <= 5, "Slime packs contain the increased three to five members")
		for point: Vector2 in entry.members as Array:
			if not bool(habitats.call("slime_support", point)): wet_safe = false
			if bool(habitats.call("is_water", point)): water_members += 1
			var banks: Vector4 = (habitats.get("river") as RefCounted).call("banks_at", point.y) as Vector4
			if not bool(habitats.call("is_bridge", point)):
				if point.x < banks.x: west_spawns += 1
				if point.x > banks.y: east_spawns += 1
	check(wet_safe and water_members == 0, "Every Slime spawn is on dry ground beside the river")
	var west_candidates: int = 0
	var east_candidates: int = 0
	for cell: Vector2i in slimes.get("_allowed") as Dictionary:
		var point: Vector2 = Vector2(cell * 16) + Vector2.ONE * 8.0
		if bool(habitats.call("is_bridge", point)): continue
		var banks: Vector4 = (habitats.get("river") as RefCounted).call("banks_at", point.y) as Vector4
		if point.x < banks.x: west_candidates += 1
		if point.x > banks.y: east_candidates += 1
	check(west_candidates > 0 and east_candidates > 0, "Dry Slime spawn candidates cover both river banks")
	var excluded_castle: int = 0
	for cell: Vector2i in habitats.get("castle_cells") as Dictionary:
		var point: Vector2 = Vector2(cell * 16) + Vector2.ONE * 8.0
		var banks: Vector4 = (habitats.get("river") as RefCounted).call("banks_at", point.y) as Vector4
		if banks.w > 0.5 and point.x < banks.x and point.x >= banks.x - 112.0 and float(world.call("_terrain_and_warp_height", point)) > 12.0:
			excluded_castle += 1
			if bool(habitats.call("slime_support", point)): wet_safe = false
	check(excluded_castle > 0 and wet_safe, "Every upper-left castle-bank candidate is excluded from the Slime habitat")
	check(east_spawns > west_spawns, "The seeded production sample favors Slime spawns on the right bank")
	var bridge_count: int = 0
	var river: RefCounted = habitats.get("river") as RefCounted
	for deck: Rect2 in river.get("bridges") as Array:
		check(is_equal_approx(float(slimes.call("spawn_weight", deck.get_center())), 0.20), "Bridge Slime spawn acceptance is reduced by 80 percent")
		bridge_count += 1
	check(bridge_count > 0 and not bool(habitats.call("slime_support", castle_point)), "River habitat stays near the river instead of unrelated castle interiors")
	if not slime_packs.is_empty():
		var anchor: Vector2 = slime_packs[0].get("anchor") as Vector2
		await _visit(_find_point(habitats, anchor, false))
		await frames(100)
		var dry_movement: bool = true
		for index: int in range(180):
			await frames(1)
			for actor: Node2D in get_nodes_in_group(&"slimes"):
				if bool(habitats.call("is_water", actor.global_position)): dry_movement = false
		check(dry_movement, "Approach, jumps and retreats keep Slimes outside the river")
		await capture("river_slimes")
		if rendered: await _real_input_review()
		slime_packs = slimes.call("all_packs") as Array
	if not slime_packs.is_empty():
		var live: Array = slime_packs[0].get("members") as Array
		if not live.is_empty():
			var slime: CharacterBody2D = live[0] as CharacterBody2D
			var position_on_bank: Vector2 = _find_point(habitats, slime_packs[0].get("anchor") as Vector2, false)
			slime.global_position = position_on_bank
			slime.set("floor_height", float(world.call("_terrain_and_warp_height", position_on_bank)))
			var manager: Node2D = world.get_node("EnemyRemains") as Node2D
			var count_before: int = int(manager.call("total_count"))
			slime.call("take_damage", 999.0)
			await frames(45)
			check(int(manager.call("total_count")) > count_before, "Slime's last death frame remains on the bank")
			world.get_node("InsectZones").call("set_palette_variant", 1)
			check(int(manager.call("total_count")) > count_before, "Insect palette previews preserve the Slime puddle palette")
			world.get_node("InsectZones").call("set_palette_variant", 0)
			await capture("slime_remains")
	var encounter: Node2D = (world.get_node("SpiritHordes").get("encounters") as Array)[0] as Node2D
	player.position = encounter.get("arena_center") as Vector2
	player.snap_floor_height()
	encounter.call("begin")
	check(bool(skulls.get("suspended")) and bool(slimes.get("suspended")), "Altar events suspend both ambient species synchronously")
	encounter.call("_on_player_defeated")
	await frames(3)
	check(not bool(skulls.get("suspended")) and not bool(slimes.get("suspended")), "Aborting an altar resumes both habitats")
	report["world"] = {"skull_packs": skulls.get("spawn_total"), "slime_packs": slimes.get("spawn_total"), "water_spawns": water_members, "west_bank_candidates": west_candidates, "east_bank_candidates": east_candidates, "west_spawns": west_spawns, "east_spawns": east_spawns, "excluded_castle_candidates": excluded_castle, "bridges": bridge_count, "skull_logs": skulls.get("spawn_log"), "slime_logs": slimes.get("spawn_log")}
	world.queue_free()
	await frames(3)
	check(get_nodes_in_group(&"slimes").is_empty() and get_nodes_in_group(&"flying_skulls").is_empty(), "Scene cleanup leaves no new enemy bodies")


func _input_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _trigger(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.size * 0.5
	Input.parse_input_event(event)


func _real_input_review() -> void:
	player.set_physics_process(true)
	var shooter: Node2D = player.get_node("BoosterShooter") as Node2D
	shooter.connect("shot_fired", func() -> void: _shots += 1)
	for slime: Node in get_nodes_in_group(&"slimes"):
		slime.connect("damaged", func(_amount: float, _health: float) -> void: _damage_events += 1)
	await frames(2)
	var started: int = Time.get_ticks_usec()
	var previous: int = started
	var previous_position: Vector2 = player.global_position
	var travel: float = 0.0
	var times: Array[float] = []
	var held: Key = KEY_NONE
	var shooting: bool = false
	var jump_captured: bool = false
	var fight_captured: bool = false
	while Time.get_ticks_usec() - started < 8000000:
		await process_frame
		var now: int = Time.get_ticks_usec()
		var elapsed: float = (now - started) / 1000000.0
		times.append((now - previous) / 1000.0)
		previous = now
		travel += previous_position.distance_to(player.global_position)
		previous_position = player.global_position
		var code: Key = KEY_W if int(elapsed / 0.38) % 2 == 0 else KEY_S
		if code != held:
			if held != KEY_NONE: _input_key(held, false)
			held = code
			_input_key(held, true)
		var target: Node2D = null
		for candidate: Node2D in get_nodes_in_group(&"slimes"):
			if target == null or candidate.global_position.distance_squared_to(player.global_position) < target.global_position.distance_squared_to(player.global_position): target = candidate
			if not jump_captured and int(candidate.get("state")) == 2 and float(candidate.get("jump_height")) > 12.0:
				jump_captured = true
				await capture("slime_jump")
		if target != null:
			var aim: Vector2 = target.global_position - Vector2(0, 8.0 + float(target.get("floor_height")) + float(target.get("jump_height")))
			shooter.set("aim_screen_override", world.get_viewport().get_canvas_transform() * aim)
		if elapsed > 2.5 and not shooting:
			shooting = true
			_trigger(true)
		if elapsed > 5.0 and not fight_captured:
			fight_captured = true
			await capture("live_river_combat")
	if held != KEY_NONE: _input_key(held, false)
	_trigger(false)
	player.set_physics_process(false)
	times.sort()
	report["rendered_input"] = {"seconds": (Time.get_ticks_usec() - started) / 1000000.0, "traveled_px": travel, "shots": _shots, "projectile_hits": _damage_events, "frame_p50_ms": times[int(times.size() * 0.5)], "frame_p95_ms": times[int(times.size() * 0.95)], "frame_max_ms": times[-1]}
	check(travel > 150.0 and _shots > 5 and _damage_events > 0, "Rendered river combat exercises actual movement, firing and projectile hits")
	check(jump_captured, "Rendered river combat includes the airborne Slime sprites")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(480, 270)
	world = Node2D.new()
	root.add_child(world)
	player = PLAYER.instantiate() as Player
	player.arena_bounds = Rect2(-1000, -1000, 6000, 6000)
	player.movement_bounds = player.arena_bounds
	world.add_child(player)
	player.position = Vector2(800, 800)
	player.set_physics_process(false)
	player.get_node("BoosterShooter").set_process(false)
	player.add_child(PARRY.new() as Node2D)
	await frames(3)
	_assets()
	await _skulls()
	await _slime_cycle()
	await _slam_rules()
	await _world()
	report["checks"] = checks
	report["failures"] = failures
	var output: FileAccess = FileAccess.open(OUT + "regression.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("BIOME_ENEMIES_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", checks, " checks")
	quit(0 if failures.is_empty() else 1)
