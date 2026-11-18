extends SceneTree
## Real E activation, terrain-clipped physics, victory, fatal damage and retry.

const REGION: Script = preload("res://scripts/dungeon/pedestal_arena_region.gd")

var failures: Array[String] = []
var rendered: bool = false
var arena: Node2D = null
var player: Player = null
var forbidden_cells: Dictionary = {}
var region_report: Array[Dictionary] = []


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func wait_until(condition: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())


func ticks(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func place(point: Vector2) -> void:
	player.position = point
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.snap_floor_height()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	player.reset_physics_interpolation()


func press_e() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://output/pedestal_arenas")
	root.get_texture().get_image().save_png("res://output/pedestal_arenas/" + label + ".png")


func capture_region(encounter: Node2D, label: String) -> void:
	if not rendered:
		return
	var region: Dictionary = encounter.get("arena_region") as Dictionary
	var bounds: Rect2 = (region.get("bounds", Rect2()) as Rect2).grow(80.0)
	var camera: Camera2D = Camera2D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position = bounds.get_center()
	camera.zoom = Vector2.ONE * minf(450.0 / bounds.size.x, 245.0 / bounds.size.y)
	arena.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	await process_frame
	await capture(label)
	camera.queue_free()
	var player_camera: Camera2D = player.get_node("Camera2D") as Camera2D
	player_camera.make_current()
	player_camera.reset_smoothing()
	player_camera.force_update_scroll()
	await process_frame


func read_forbidden_cells() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var composition: Dictionary = preload("res://scripts/dungeon/ldtk_level_composition.gd").compose(source, "Room_2")
	for layer: Dictionary in composition.get("layers", []):
		if str(layer.get("__identifier", "")) != "Gameplay" or not bool(layer.get("visible", true)):
			continue
		var width: int = int(layer.get("__cWid", 1))
		var grid: int = int(layer.get("__gridSize", 16))
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		var values: Array = layer.get("intGridCsv", []) as Array
		for index: int in range(values.size()):
			if int(values[index]) not in [1, 2, 3, 6, 7]:
				continue
			var point: Vector2 = Vector2(index % width, floori(float(index) / float(width))) * float(grid) + offset
			for y: int in range(int(float(grid) / 16.0)):
				for x: int in range(int(float(grid) / 16.0)):
					forbidden_cells[Vector2i((point / 16.0).floor()) + Vector2i(x, y)] = true


func validate_authoring_controls() -> void:
	var allowed: Dictionary = {}
	for y: int in range(20):
		for x: int in range(20):
			allowed[Vector2i(x, y)] = true
	var arena_entity: Dictionary = {"__identifier": "PedestalArena", "px": [1000, 1000], "width": 128, "height": 128,
		"__pivot": [0.5, 0.5], "fieldInstances": [
			{"__identifier": "EncounterId", "__value": "regression_anchor_fixture"},
			{"__identifier": "RadiusPx", "__value": 192},
			{"__identifier": "KillTarget", "__value": 40}]}
	var layers: Array = [{"visible": true, "entityInstances": [
		{"__identifier": "HordePedestal", "px": [160, 160], "width": 64, "height": 64, "__pivot": [0.5, 0.5],
			"fieldInstances": [{"__identifier": "EncounterId", "__value": "regression_anchor_fixture"}]},
		arena_entity]}]
	var previous_area: float = 0.0
	for requested: int in [192, 64]:
		(arena_entity.fieldInstances[1] as Dictionary)["__value"] = requested
		var adapter: Node2D = preload("res://scripts/dungeon/ldtk_spirit_hordes.gd").new() as Node2D
		adapter.name = "RegressionAnchorFixture"
		arena.add_child(adapter)
		adapter.call("build", layers, player, arena.get_node("Gameplay"), Callable(arena, "is_ground_surface_point"), null, Callable(), allowed)
		var fixtures: Array = adapter.get("encounters") as Array
		check(fixtures.size() == 1, "Fixture creates exactly one E-only encounter")
		var fixture: Node2D = fixtures[0] as Node2D
		check((fixture.get("arena_center") as Vector2).is_equal_approx(Vector2(160, 160)), "Moving the arena entity cannot detach combat center from the matching pedestal")
		check(is_equal_approx(float(fixture.get("arena_radius")), float(requested)), "RadiusPx overrides the entity's drawn width and height")
		check(not bool(fixture.get("activate_on_enter")) and int(fixture.get("kill_target")) == 40, "Radius changes preserve E activation and forty-kill gameplay")
		var region: Dictionary = fixture.get("arena_region") as Dictionary
		var area: float = float(region.get("area", 0.0))
		check(area > 0.0 and (previous_area == 0.0 or area < previous_area), "Changing only RadiusPx changes the final combat footprint")
		previous_area = area
		adapter.queue_free()
		await ticks(1)


func validate_region(encounter: Node2D, pedestal: Node2D) -> void:
	var region: Dictionary = encounter.get("arena_region") as Dictionary
	var center: Vector2 = region.get("center", Vector2.INF) as Vector2
	check(center.is_equal_approx(pedestal.position), "Arena remains anchored to its matching pedestal")
	var cells: Dictionary = region.get("cells", {}) as Dictionary
	check(not cells.is_empty(), "Each pedestal has a valid playable combat region")
	check(REGION.point_is_inside(region, center, 9.0), "Player fits on the pedestal with clearance")
	var raster: float = float(region.get("raster_size", 4))
	var radius: float = float(encounter.get("arena_radius"))
	for cell: Vector2i in cells:
		var point: Vector2 = (Vector2(cell) + Vector2.ONE * 0.5) * raster
		check(bool(arena.call("is_ground_surface_point", point)), "Combat region never extends into river water or void")
		check(not forbidden_cells.has(Vector2i((point / 16.0).floor())), "Combat region excludes authored limits, solids, gaps, doors and hazards")
		check(point.distance_to(center) <= radius + raster, "Combat region respects the requested radius around its pedestal")
	var bounds: Rect2 = region.get("bounds", Rect2()) as Rect2
	region_report.append({"id": str(encounter.get("encounter_id")), "center": [center.x, center.y], "radius": radius,
		"area": float(region.get("area", 0.0)), "bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"contours": (region.get("contours", []) as Array).size()})


func perimeter_probes(region: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for contour: PackedVector2Array in region.get("contours", []):
		var stride: int = maxi(1, int(contour.size() / 12.0))
		for index: int in range(0, contour.size(), stride):
			var next: int = (index + 1) % contour.size()
			var delta: Vector2 = contour[next] - contour[index]
			if delta.length_squared() < 0.01:
				continue
			var middle: Vector2 = (contour[index] + contour[next]) * 0.5
			var inward: Vector2 = delta.orthogonal().normalized()
			if not REGION.point_is_inside(region, middle + inward * 20.0, 9.0):
				inward = -inward
			if not REGION.point_is_inside(region, middle + inward * 20.0, 9.0):
				continue
			if REGION.point_is_inside(region, middle - inward * 20.0):
				continue
			result.append({"origin": middle + inward * 20.0 - Vector2(0, 3), "motion": -inward * 60.0})
	return result


func check_perimeter(encounter: Node2D, blocking: bool) -> Array[Dictionary]:
	var fence: StaticBody2D = encounter.get("arena_boundary") as StaticBody2D
	var probes: Array[Dictionary] = perimeter_probes(encounter.get("arena_region") as Dictionary)
	check(probes.size() >= 4, "Clipped perimeter exposes several independent traversal probes")
	# Isolate the ritual boundary from tree trunks, bridge rails and map limits.
	var previous_mask: int = player.collision_mask
	player.collision_mask = 16
	for probe: Dictionary in probes:
		var collision: KinematicCollision2D = KinematicCollision2D.new()
		var hit: bool = player.test_move(Transform2D(0.0, probe.origin as Vector2), probe.motion as Vector2, collision)
		check(hit == blocking, "Perimeter blocks only while the ritual is active")
		if blocking and hit:
			check(collision.get_collider() == fence, "Containment comes from the clipped ritual boundary")
	player.collision_mask = previous_mask
	return probes


func _run() -> void:
	root.size = Vector2i(960, 540)
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	read_forbidden_cells()
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))), "Arrival finishes")
	await validate_authoring_controls()
	player.contact_invulnerability = 1000.0
	var encounters: Array = arena.get_node("SpiritHordes").get("encounters") as Array
	var pedestals: Array = arena.get_node("HordePedestals").get("pedestals") as Array
	check(encounters.size() == 6 and pedestals.size() == 7, "Six playable events; central remains reserved")
	var first: Node2D = null
	var second: Node2D = null
	for pedestal: Node2D in pedestals:
		if (pedestal.get("data") as Dictionary).EncounterId == "room_2_final_center":
			check(pedestal.get("encounter") == null, "Central has no ritual or final-warp implementation")
			continue
		place(pedestal.position)
		await ticks()
		check(bool(pedestal.call("can_activate")), "Each external pedestal offers E when standing on it")
		var encounter: Node2D = pedestal.get("encounter") as Node2D
		validate_region(encounter, pedestal)
		var boundary: StaticBody2D = encounter.get("arena_boundary") as StaticBody2D
		check(boundary != null and not bool(boundary.get("active")) and not boundary.visible, "Each arena is physically and visually open before activation")
		check((encounter.get("actors") as Array).is_empty(), "Standing on a pedestal does not spawn automatically")
		check_perimeter(encounter, false)
		if str(encounter.get("encounter_id")) == "room_2_forest_west":
			first = pedestal
			await capture_region(encounter, "01_lower_west_waiting")
		if str(encounter.get("encounter_id")) == "room_2_forest_east": second = pedestal
	check(first != null and second != null, "Both lower pedestal event fixtures exist")
	await capture_region(second.get("encounter") as Node2D, "02_lower_east_waiting")
	place(first.position)
	await ticks()
	var active: Node2D = first.get("encounter") as Node2D
	var fence: StaticBody2D = active.get("arena_boundary") as StaticBody2D
	var radius: float = float(active.get("arena_radius"))
	var region: Dictionary = active.get("arena_region") as Dictionary
	var center: Vector2 = region.get("center") as Vector2
	press_e()
	await ticks()
	check(int(active.get("phase")) == 1 and bool(fence.get("active")) and fence.visible, "E activates the horde and shows/closes its clipped perimeter")
	check(not (active.get("actors") as Array).is_empty(), "Monsters spawn only after E")
	for actor: Node2D in active.get("actors") as Array:
		var spawn: Vector2 = actor.get_meta("spawn_position") as Vector2
		check(spawn.distance_to(center) > radius, "Spirits arrive from outside the arena")
		check(not (actor.get_meta("spawn_viewport") as Rect2).grow(20).has_point(spawn), "Arrival never pops into the visible camera")
	var probes: Array[Dictionary] = check_perimeter(active, true)
	var dash_probe: Dictionary = probes[0]
	var original_mask: int = player.collision_mask
	player.collision_mask = 16
	place(dash_probe.origin as Vector2)
	check(player.try_dash((dash_probe.motion as Vector2).normalized()), "Player can dash toward the clipped perimeter")
	await create_timer(0.3).timeout
	check(REGION.point_is_inside(region, player.position + Vector2(0, 3), 4.0), "Dash cannot escape through a clipped edge or corner")
	player.collision_mask = original_mask
	place(center)
	await capture_region(active, "03_lower_west_active")
	place(center)
	var other: Node2D = second.get("encounter") as Node2D
	player.position = second.position
	check(not bool(other.call("can_begin")), "Another ritual cannot start while this one is active")
	place(center)
	# Forty real deaths exercise stages, gauge and normal completion.
	for index: int in range(40):
		var actors: Array = active.get("actors") as Array
		if actors.is_empty(): active.call("_spawn_one")
		actors = active.get("actors") as Array
		if actors.is_empty():
			check(false, "Horde can provide the next kill")
			break
		(actors[0] as Node2D).call("take_damage", 3.0)
		if index % 10 == 9: await ticks(1)
	await ticks()
	check(int(active.get("phase")) == 2 and int(active.get("defeated_count")) == 40, "Forty kills complete the ritual")
	check(float(first.get("progress")) == 1.0, "Completion fills the pedestal")
	check(not bool(fence.get("active")) and (active.get("actors") as Array).is_empty(), "Victory removes containment and remaining spirits")
	check_perimeter(active, false)
	place(first.position)
	press_e()
	await ticks()
	check(int(active.get("phase")) == 2, "Completed ritual does not restart from repeated E")
	place(second.position)
	await ticks()
	press_e()
	await ticks()
	check(int(other.get("phase")) == 1, "Another pedestal can start after the earlier victory")
	check_perimeter(other, true)
	await capture_region(other, "04_lower_east_active")
	player.receive_skybreaker_hit(999.0)
	await ticks()
	var second_fence: StaticBody2D = other.get("arena_boundary") as StaticBody2D
	check(player.dead and int(other.get("phase")) == 3, "Zero health aborts the active ritual")
	check(not bool(second_fence.get("active")) and (other.get("actors") as Array).is_empty(), "Defeat releases the circle and stops every spawn")
	check_perimeter(other, false)
	check(float(second.get("progress")) < 1.0, "Defeat does not grant victory or full charge")
	var defeat: CanvasLayer = arena.get_node("PlayerDefeat") as CanvasLayer
	check(await wait_until(func() -> bool: return bool(defeat.get("menu_ready"))), "Existing defeat screen remains usable")
	await capture("defeat_released")
	var old_id: int = arena.get_instance_id()
	defeat.call("retry")
	check(await wait_until(func() -> bool: return current_scene != null and current_scene.get_instance_id() != old_id), "Retry reloads the arrival warp")
	check(await wait_until(func() -> bool: return bool(current_scene.get("entry_complete"))), "Retry arrival finishes")
	check(not paused and is_equal_approx(Engine.time_scale, 1.0), "Retry restores normal time")
	for encounter: Node2D in current_scene.get_node("SpiritHordes").get("encounters") as Array:
		check(int(encounter.get("phase")) == 0 and (encounter.get("actors") as Array).is_empty(), "Restart returns to idle, open arenas with no automatic spawns")
	DirAccess.make_dir_recursive_absolute("res://output/pedestal_arenas")
	var report: FileAccess = FileAccess.open("res://output/pedestal_arenas/regions.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(region_report, "\t") + "\n")
	print("PEDESTAL_ARENA_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)
