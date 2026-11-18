extends SceneTree
## Flight, floor/void decisions, timed fade, foot interaction and room-owned cleanup.
const REMAINS: Script = preload("res://scripts/visual/enemy_remains.gd")
const PIECE: Script = preload("res://scripts/visual/enemy_remains_piece.gd")
const GHOST: Script = preload("res://scripts/enemies/spirit_ghost.gd")
const ARENA: PackedScene = preload("res://scenes/dungeon/ldtk_arena.tscn")
var failures: Array[String] = []
var rendered: bool = false
var fixture: Node2D = null


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func floor_query(world_point: Vector2) -> bool:
	var local: Vector2 = fixture.to_local(world_point)
	return Rect2(0, 0, 256, 256).has_point(local) and not Rect2(112, 112, 32, 32).has_point(local)


func all_settled(manager: Node2D) -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for chunk: Node2D in (manager.get("_chunks") as Dictionary).values():
		for piece: RefCounted in chunk.get("pieces") as Array:
			result.append(piece)
	return result


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/enemy_remains"))
	check(root.get_texture().get_image().save_png("res://output/enemy_remains/" + label + ".png") == OK, "Capture saves")


func key_d(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_D
	event.physical_keycode = KEY_D
	event.pressed = pressed
	Input.parse_input_event(event)


func wait_entry(arena: Node2D) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(arena.get("entry_complete")), "Arrival finishes")


func open_floor_center(arena: Node2D) -> Vector2:
	var cells: Dictionary = arena.call("_combat_allowed_cells") as Dictionary
	for cell: Vector2i in cells:
		var point: Vector2 = Vector2(cell * 16) + Vector2.ONE * 8.0
		var valid: bool = true
		for y: int in range(-2, 3):
			for x: int in range(-2, 3):
				if not bool(arena.call("is_ground_surface_point", point + Vector2(x, y) * 16.0)): valid = false
		if valid: return point
	check(false, "Current LDtk room has open floor for the remains fixture")
	return Vector2.ZERO


func check_lifetime() -> void:
	var manager: Node2D = REMAINS.new() as Node2D
	fixture.add_child(manager)
	manager.call("configure", floor_query)
	manager.set_physics_process(false)
	var profile: Resource = manager.get("spirit_profile") as Resource
	profile.set("minimum_pieces", 1)
	profile.set("maximum_pieces", 1)
	profile.set("minimum_speed", 0.0)
	profile.set("maximum_speed", 0.0)
	profile.set("minimum_lift", 0.0)
	profile.set("maximum_lift", 0.0)
	check(float(profile.get("lifetime")) == 15.0 and is_equal_approx(float(profile.get("fade_duration")), 0.35), "Debris waits fifteen seconds then fades quickly")
	var first_ground: Vector2 = fixture.to_global(Vector2(64, 64))
	manager.call("emit_spirit", first_ground, first_ground, Vector2.ZERO)
	for index: int in range(90):
		manager.call("_physics_process", 1.0 / 60.0)
	var first: RefCounted = all_settled(manager)[0]
	check(is_equal_approx(float(first.get("expires_at")), 15.0), "Lifetime starts at spawn, before flight or landing")
	manager.set("_elapsed", 8.0)
	var second_ground: Vector2 = fixture.to_global(Vector2(192, 64))
	manager.call("emit_spirit", second_ground, second_ground, Vector2.ZERO)
	for index: int in range(90):
		manager.call("_physics_process", 1.0 / 60.0)
	check(int(manager.call("settled_count")) == 2, "Different generations can sleep in separate chunks")
	manager.set("_elapsed", 14.90)
	manager.call("_physics_process", 0.01)
	check(float(first.get("opacity")) == 1.0 and int(manager.call("total_count")) == 2, "Scraps stay opaque until their own fifteen-second deadline")
	manager.set("_previous_feet", Vector2(61, 64))
	check(bool(manager.call("_kick_if_near", first, Vector2(67, 64), Vector2.RIGHT, 80.0)), "An almost-expired scrap can still be kicked")
	var first_chunk: Node2D = (manager.get("_chunks") as Dictionary).get(Vector2i.ZERO) as Node2D
	manager.call("_wake", first, first_chunk)
	check(is_equal_approx(float(first.get("expires_at")), 15.0), "Kicking a scrap never restarts its lifetime")
	manager.set("_elapsed", 15.17)
	manager.call("_physics_process", 0.005)
	check(float(first.get("opacity")) > 0.45 and float(first.get("opacity")) < 0.55, "An airborne kicked scrap fades progressively instead of popping")
	check(int(manager.call("total_count")) == 2, "Newer remains survive while older ones fade")
	manager.set("_elapsed", 15.36)
	manager.call("_physics_process", 0.005)
	check(int(manager.call("total_count")) == 1, "Airborne scraps are released after the short fade")
	var second: RefCounted = all_settled(manager)[0]
	check(float(second.get("opacity")) == 1.0 and is_equal_approx(float(second.get("expires_at")), 23.0), "Each emission keeps its own spawn deadline")
	manager.set("_elapsed", 23.17)
	manager.call("_physics_process", 0.005)
	check(float(second.get("opacity")) > 0.45 and float(second.get("opacity")) < 0.55, "Sleeping scraps fade without returning to flight simulation")
	manager.set("_elapsed", 23.36)
	manager.call("_physics_process", 0.005)
	check(int(manager.call("total_count")) == 0 and (manager.get("_chunks") as Dictionary).is_empty(), "Expired scraps and empty draw chunks are completely removed")
	manager.queue_free()
	await ticks(2)


func _run() -> void:
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	fixture = Node2D.new()
	fixture.position = Vector2(20, 40)
	root.add_child(fixture)
	var manager: Node2D = REMAINS.new() as Node2D
	fixture.add_child(manager)
	manager.call("configure", floor_query)
	var profile: Resource = manager.get("spirit_profile") as Resource
	profile.set("minimum_pieces", 5)
	profile.set("maximum_pieces", 5)
	var ground: Vector2 = fixture.to_global(Vector2(64, 64))
	var center: Vector2 = ground + Vector2(0, -8)
	manager.call("emit_spirit", center, ground, Vector2.RIGHT)
	check(int(manager.call("total_count")) == 5, "One death creates a few scraps")
	var particles: Array = manager.get("active") as Array
	for piece: RefCounted in particles:
		var origin: Vector2 = (piece.get("ground") as Vector2) - Vector2(0, float(piece.get("height")))
		check(manager.to_global(origin).is_equal_approx(center), "Every scrap starts at the visual center of mass")
	await ticks(10)
	check(float(particles[0].get("height")) > 8.0, "Fragments visibly jump upward before falling")
	await ticks(85)
	check(int(manager.call("settled_count")) == 5 and (manager.get("active") as Array).is_empty(), "Arena scraps stop simulating and remain on the floor")
	var rested: Array[RefCounted] = all_settled(manager)
	var positions: Array[Vector2] = []
	for piece: RefCounted in rested:
		positions.append(piece.get("ground") as Vector2)
	await ticks(150)
	check(int(manager.call("total_count")) == 5, "Rested scraps remain before the fifteen-second deadline")
	for index: int in range(rested.size()):
		check((rested[index].get("ground") as Vector2) == positions[index], "Sleeping scraps remain still")
	# No ground under the landing point: a short downward fall removes the scraps.
	profile.set("minimum_speed", 0.0)
	profile.set("maximum_speed", 0.0)
	profile.set("minimum_lift", 60.0)
	profile.set("maximum_lift", 60.0)
	var void_ground: Vector2 = fixture.to_global(Vector2(128, 128))
	manager.call("emit_spirit", void_ground + Vector2(0, -8), void_ground, Vector2.ZERO)
	await ticks(33)
	var falling: int = 0
	for piece: RefCounted in manager.get("active") as Array:
		if bool(piece.get("falling")):
			falling += 1
	check(falling == 5, "Pieces fall below the floor plane when landing in the void")
	await ticks(20)
	check(int(manager.call("total_count")) == 5, "Void pieces are removed, floor pieces persist")
	# Flying over a gap must not remove a scrap that lands on the far side.
	var crossing: RefCounted = PIECE.new()
	crossing.set("ground", Vector2(103, 128))
	crossing.set("previous_ground", Vector2(103, 128))
	crossing.set("height", 10.0)
	crossing.set("previous_height", 10.0)
	crossing.set("velocity", Vector2(95, 0))
	crossing.set("lift_velocity", 85.0)
	crossing.set("profile", profile)
	profile.set("air_drag", 0.1)
	(manager.get("active") as Array).append(crossing)
	await ticks(10)
	check((crossing.get("ground") as Vector2).x > 112 and not bool(crossing.get("falling")), "Airborne scraps can travel across the void")
	await ticks(90)
	check(bool(crossing.get("sleeping")) and (crossing.get("ground") as Vector2).x > 144, "Scrap that clears the gap persists on the far side")
	# Rounding at a tile edge must not silently discard a piece or leave it floating.
	var edge: RefCounted = PIECE.new()
	edge.set("ground", Vector2(111.9, 128))
	edge.set("previous_ground", Vector2(111.9, 128))
	edge.set("profile", profile)
	(manager.get("active") as Array).append(edge)
	await ticks(2)
	check(bool(edge.get("falling")) and (manager.get("active") as Array).has(edge), "Pixel rounding over a void edge enters the fall state")
	await ticks(20)
	check(not (manager.get("active") as Array).has(edge), "Rounded edge fall completes its cleanup")
	await check_lifetime()
	fixture.queue_free()
	await ticks(2)
	# Production integration: real ghost death, footsteps and warp scene replacement.
	var arena: Node2D = ARENA.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	var encounter: Node2D = (arena.get_node("SpiritHordes").get("encounters") as Array)[0] as Node2D
	encounter.set_physics_process(false)
	await wait_entry(arena)
	var player: Player = arena.get_node("Nox") as Player
	# Resolve a floor patch from the current map; old hard-coded coordinates became void.
	var combat_center: Vector2 = open_floor_center(arena)
	player.position = combat_center - Vector2(24, 0)
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	manager = arena.get_node("EnemyRemains") as Node2D
	profile = manager.get("spirit_profile") as Resource
	profile.set("minimum_pieces", 5)
	profile.set("maximum_pieces", 5)
	var ghost: Node2D = GHOST.new() as Node2D
	ghost.position = combat_center
	ghost.set("remains_system", manager)
	arena.add_child(ghost)
	var visual_center: Vector2 = ghost.call("get_visual_center_of_mass") as Vector2
	check(visual_center.y < ghost.global_position.y and visual_center.distance_to(ghost.global_position) < 18.0, "Ghost mass center follows the visible sprite")
	ghost.call("take_damage", 1.0)
	check(int(manager.call("total_count")) == 0, "Nonlethal hits create no remains")
	ghost.call("take_damage", 2.0)
	check(int(manager.call("total_count")) == 5, "Lethal combat damage emits remains")
	ghost.call("take_damage", 6.0)
	check(int(manager.call("total_count")) == 5, "Death cannot emit twice")
	await ticks(8)
	await capture("spirit_burst")
	await ticks(90)
	check(int(manager.call("settled_count")) == 5, "Real Room_1 floor keeps the fragments")
	var dismissed: Node2D = GHOST.new() as Node2D
	dismissed.position = combat_center
	dismissed.set("remains_system", manager)
	arena.add_child(dismissed)
	dismissed.call("dismiss")
	var consumed: Node2D = GHOST.new() as Node2D
	consumed.position = combat_center
	consumed.set("remains_system", manager)
	arena.add_child(consumed)
	consumed.call("consume_on_contact")
	check(int(manager.call("total_count")) == 5, "Contact and encounter cleanup do not create combat remains")
	await ticks(10)
	await capture("rested")
	rested = all_settled(manager)
	if rested.is_empty():
		push_error("No settled remains available for the footstep fixture")
		quit(1)
		return
	var target: RefCounted = rested[0]
	var original: Vector2 = target.get("ground") as Vector2
	player.position = original - Vector2(18, 7)
	player.reset_physics_interpolation()
	manager.set("_sampled_player", false)
	await ticks(2)
	var player_origin: Vector2 = player.position
	key_d(true)
	await ticks(24)
	key_d(false)
	check(player.position.x - player_origin.x > 33.0, "Player walks over debris without being blocked")
	check((target.get("ground") as Vector2).distance_to(original) > 2.0, "Footsteps kick resting scraps")
	await capture("foot_kick")
	await ticks(90)
	check(int(manager.call("total_count")) == 5 and int(manager.call("settled_count")) == 5, "Kicked scraps settle again and remain")
	var expired_at: float = float(all_settled(manager)[0].get("expires_at"))
	manager.set("_elapsed", expired_at + 0.17)
	manager.call("_physics_process", 0.005)
	await capture("timed_fade")
	manager.set("_elapsed", expired_at + 0.36)
	manager.call("_physics_process", 0.005)
	await ticks(2)
	check(int(manager.call("total_count")) == 0 and (manager.get("_chunks") as Dictionary).is_empty(), "Real Room_1 remains finish fading and release all floor chunks")
	await capture("expired")
	var rules: Node2D = arena.get_node("Gameplay") as Node2D
	rules.call("set_condition", "spirit_horde_1_clear", true)
	var gate: Node2D = (arena.get_node("Warps").get("gates") as Array)[1] as Node2D
	arena.call("_begin_warp_travel", gate)
	var deadline: int = Time.get_ticks_msec() + 4000
	while is_instance_valid(arena) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(manager), "Changing the scene destroys all old scraps and draw chunks")
	var next_room: Node2D = current_scene as Node2D
	check(is_instance_valid(next_room) and next_room.scene_file_path == "res://scenes/tutorial_arena.tscn" and not next_room.has_node("EnemyRemains"), "Asterion arrival contains none of the old room scraps")
	if is_instance_valid(next_room):
		next_room.queue_free()
	await ticks(3)
	print("ENEMY_REMAINS_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " | failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
