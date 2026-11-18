extends SceneTree
## Combat footprint: bounded radius, disconnected terrain, holes and swept containment.

const REGION: Script = preload("res://scripts/dungeon/pedestal_arena_region.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _ground() -> Dictionary:
	var result: Dictionary = {}
	for y: int in range(18):
		for x: int in range(20):
			# Two river columns, one isolated solid obstacle and a separate east bank.
			if x in [14, 15] or Vector2i(x, y) == Vector2i(6, 10):
				continue
			result[Vector2i(x, y)] = true
	return result


func _run() -> void:
	var ground: Dictionary = _ground()
	var center: Vector2 = Vector2(160, 160)
	var small: Dictionary = REGION.build(center, 64.0, ground)
	var large: Dictionary = REGION.build(center, 192.0, ground)
	check((small.get("center") as Vector2).is_equal_approx(center), "The requested center remains the pedestal, not the clipped area's centroid")
	check((large.get("center") as Vector2).is_equal_approx(center), "Clipping cannot recenter an arena toward free terrain")
	check(float(large.get("area", 0.0)) > float(small.get("area", 0.0)), "Increasing only X/radius expands the reachable combat footprint")
	var small_cells: Dictionary = small.get("cells", {}) as Dictionary
	var large_cells: Dictionary = large.get("cells", {}) as Dictionary
	check(not small_cells.is_empty() and not large_cells.is_empty(), "Both authored radii produce a playable region")
	for cell: Vector2i in small_cells:
		check(large_cells.has(cell), "Increasing radius preserves every previously allowed cell")
	var raster: float = float(large.get("raster_size", 0))
	check(raster > 0.0, "Region exposes its raster spacing")
	for cell: Vector2i in large_cells:
		var point: Vector2 = (Vector2(cell) + Vector2.ONE * 0.5) * raster
		check(ground.has(Vector2i((point / 16.0).floor())), "Every combat sample lies on allowed authored terrain")
		check(point.distance_to(center) <= 192.0, "The radius remains a hard maximum around the pedestal")
	check(REGION.point_is_inside(large, center, 9.0), "Pedestal keeps clearance for the player capsule")
	check(not REGION.point_is_inside(large, Vector2(232, 160)), "River water is excluded")
	check(not REGION.point_is_inside(large, Vector2(280, 160)), "Disconnected bank cannot join the fight through the river")
	check(not REGION.point_is_inside(large, Vector2(160, 300)), "Bottom map limit is excluded")
	check(not REGION.point_is_inside(large, Vector2(104, 168)), "Solid gameplay obstacle remains a hole")
	check(REGION.point_is_inside(large, Vector2(72, 168), 9.0), "A legal path exists immediately before the obstacle")
	check(REGION.point_is_inside(large, Vector2(136, 168), 9.0), "Terrain beyond an obstacle remains accessible by going around")
	var stopped: Vector2 = REGION.clamp_motion(large, Vector2(72, 168), Vector2(136, 168), 9.0)
	check(REGION.point_is_inside(large, stopped, 9.0), "Swept clamp returns a point with full body clearance")
	check(stopped.x < 96.0, "Dash/knockback cannot tunnel through a hole into legal terrain beyond it")
	var recovered: Vector2 = REGION.closest_allowed_point(large, Vector2(360, 360), 9.0)
	check(REGION.point_is_inside(large, recovered, 9.0), "An out-of-bounds correction lands inside the same valid component")
	var contours: Array = large.get("contours", []) as Array
	check(contours.size() >= 2, "Contours retain both outer perimeter and the solid obstacle hole")
	var outline_area: float = 0.0
	for contour: PackedVector2Array in contours:
		check(contour.size() >= 3, "Every emitted outline is a closed usable polygon")
		for index: int in range(contour.size()):
			outline_area += contour[index].cross(contour[(index + 1) % contour.size()]) * 0.5
	check(is_equal_approx(absf(outline_area), float(large.get("area", -1.0))), "Contour winding subtracts holes and preserves the exact playable area")
	var bridged_ground: Dictionary = ground.duplicate()
	for y: int in [9, 10]:
		for x: int in [14, 15]:
			bridged_ground[Vector2i(x, y)] = true
	var bridged: Dictionary = REGION.build(center, 192.0, bridged_ground)
	check(REGION.point_is_inside(bridged, Vector2(280, 160), 9.0), "A real walkable bridge connects the opposite bank")
	check(REGION.point_is_inside(bridged, Vector2(240, 160), 9.0), "Bridge deck preserves sufficient body clearance")
	var crossed: Vector2 = REGION.clamp_motion(bridged, center, Vector2(280, 160), 9.0)
	check(crossed.distance_to(Vector2(280, 160)) < 1.0, "Swept containment permits legitimate movement across a bridge")
	var bridge_outside_radius: Dictionary = ground.duplicate()
	for x: int in [14, 15]:
		bridge_outside_radius[Vector2i(x, 0)] = true
	var unreachable_bridge: Dictionary = REGION.build(center, 140.0, bridge_outside_radius)
	check(not REGION.point_is_inside(unreachable_bridge, Vector2(280, 160)), "A bridge outside the requested radius cannot connect otherwise separated banks")
	var invalid: Dictionary = REGION.build(Vector2(232, 160), 192.0, ground)
	check((invalid.get("cells", {}) as Dictionary).is_empty(), "An illegal pedestal center cannot silently pick another terrain component")
	var offset: Vector2 = Vector2(640, -320)
	var shifted_ground: Dictionary = {}
	for cell: Vector2i in ground:
		shifted_ground[cell + Vector2i(offset / 16.0)] = true
	var shifted: Dictionary = REGION.build(center + offset, 192.0, shifted_ground)
	check(is_equal_approx(float(shifted.get("area", -1.0)), float(large.get("area", -2.0))), "World translation preserves clipped combat area")
	var before_bounds: Rect2 = large.get("bounds", Rect2()) as Rect2
	var after_bounds: Rect2 = shifted.get("bounds", Rect2()) as Rect2
	check(after_bounds.position.is_equal_approx(before_bounds.position + offset) and after_bounds.size.is_equal_approx(before_bounds.size), "Negative world coordinates preserve contour placement and bounds")
	print("PEDESTAL_ARENA_REGION_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)
