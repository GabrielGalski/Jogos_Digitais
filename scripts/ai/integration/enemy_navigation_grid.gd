class_name EnemyNavigationGrid
extends RefCounted
## One static clearance map per chamber/body size. Dynamic actors never block the map.
## Call invalidate() after opening doors or changing static collision geometry.

var grid: AStarGrid2D = AStarGrid2D.new()
var bounds: Rect2
var cell_size: float = 8.0
var revision: int = 0
var ready: bool = false
var builds: int = 0
var path_queries: int = 0
var build_usec: int = 0


func invalidate() -> void:
	ready = false
	revision += 1


func build(world: World2D, world_bounds: Rect2, radius: float, mask: int) -> void:
	var started: int = Time.get_ticks_usec()
	bounds = world_bounds
	grid.region = Rect2i(Vector2i.ZERO, Vector2i(ceili(bounds.size.x / cell_size), ceili(bounds.size.y / cell_size)))
	grid.cell_size = Vector2.ONE * cell_size
	grid.offset = bounds.position + Vector2.ONE * cell_size * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var shape: CircleShape2D = CircleShape2D.new()
	# Extra half diagonal protects the complete square, including smoothed segments.
	shape.radius = radius + cell_size * 0.707107 + 1.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = mask
	var safe_bounds: Rect2 = bounds.grow(-shape.radius)
	for y: int in range(grid.region.size.y):
		for x: int in range(grid.region.size.x):
			var cell: Vector2i = Vector2i(x, y)
			var point: Vector2 = grid.get_point_position(cell)
			var blocked: bool = not safe_bounds.has_point(point)
			if not blocked:
				query.transform = Transform2D(0.0, point)
				for hit: Dictionary in world.direct_space_state.intersect_shape(query, 64):
					if not hit["collider"] is CharacterBody2D:
						blocked = true
						break
			grid.set_point_solid(cell, blocked)
	ready = true
	builds += 1
	build_usec = Time.get_ticks_usec() - started


func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(((point - bounds.position) / cell_size).floor())


func is_open(point: Vector2) -> bool:
	var cell: Vector2i = cell_at(point)
	return grid.is_in_boundsv(cell) and not grid.is_point_solid(cell)


func nearest_open(point: Vector2, max_distance: float = 48.0) -> Vector2i:
	var center: Vector2i = cell_at(point)
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: float = max_distance * max_distance
	var extent: int = ceili(max_distance / cell_size)
	for y: int in range(-extent, extent + 1):
		for x: int in range(-extent, extent + 1):
			var cell: Vector2i = center + Vector2i(x, y)
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell):
				continue
			var distance: float = point.distance_squared_to(grid.get_point_position(cell))
			if distance <= best_distance:
				best = cell
				best_distance = distance
	return best


func corridor_clear(from: Vector2, to: Vector2) -> bool:
	var steps: int = maxi(1, ceili(from.distance_to(to) / (cell_size * 0.4)))
	for step: int in range(steps + 1):
		if not is_open(from.lerp(to, float(step) / float(steps))):
			return false
	return true


func find_path(from: Vector2, to: Vector2, blockers: Array[Vector3] = []) -> PackedVector2Array:
	path_queries += 1
	# Temporary occupancy belongs to this query only, not the shared static map.
	var changed: Array[Vector2i] = []
	for blocker: Vector3 in blockers:
		var center: Vector2 = Vector2(blocker.x, blocker.y)
		var cell: Vector2i = cell_at(center)
		var extent: int = ceili(blocker.z / cell_size) + 1
		for y: int in range(-extent, extent + 1):
			for x: int in range(-extent, extent + 1):
				var candidate: Vector2i = cell + Vector2i(x, y)
				if grid.is_in_boundsv(candidate) and not grid.is_point_solid(candidate) and grid.get_point_position(candidate).distance_to(center) <= blocker.z + cell_size * 0.707107:
					changed.append(candidate)
					grid.set_point_solid(candidate, true)
	var start: Vector2i = nearest_open(from)
	var goal: Vector2i = nearest_open(to)
	var result: PackedVector2Array = PackedVector2Array()
	if start.x >= 0 and goal.x >= 0:
		result = grid.get_point_path(start, goal, false)
	for cell: Vector2i in changed:
		grid.set_point_solid(cell, false)
	return result
