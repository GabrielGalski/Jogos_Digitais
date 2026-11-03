extends RefCounted
## Static terrain-clipped arena geometry. All positions stay on the logical world plane.
## Input keys are authored terrain cells; output cells use the finer raster_size grid.

const RASTER_SIZE: int = 4
const CARDINALS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


static func build(center: Vector2, radius: float, allowed_cells: Dictionary, cell_size: int = 16) -> Dictionary:
	var terrain_size: int = maxi(cell_size, 1)
	var raster_size: int = mini(RASTER_SIZE, terrain_size)
	var arena_radius: float = maxf(radius, 0.0)
	var seed_cell: Vector2i = _cell_at(center, raster_size)
	var cells: Dictionary = {}
	var result: Dictionary = {
		"center": center,
		"radius": arena_radius,
		"cell_size": terrain_size,
		"raster_size": raster_size,
		"seed": seed_cell,
		"cells": cells,
		"contours": [] as Array[PackedVector2Array],
		"bounds": Rect2(center, Vector2.ZERO),
		"area": 0.0,
	}
	if not _cell_is_allowed(seed_cell, center, arena_radius, allowed_cells, terrain_size, raster_size):
		return result
	# Flood from the pedestal, rather than keeping detached land across a river.
	# Four-way connectivity also excludes diagonally touching islands.
	var visited: Dictionary = {seed_cell: true}
	var queue: Array[Vector2i] = [seed_cell]
	var cursor: int = 0
	var minimum: Vector2i = seed_cell
	var maximum: Vector2i = seed_cell
	cells[seed_cell] = true
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in CARDINALS:
			var neighbour: Vector2i = cell + direction
			if visited.has(neighbour):
				continue
			visited[neighbour] = true
			if not _cell_is_allowed(neighbour, center, arena_radius, allowed_cells, terrain_size, raster_size):
				continue
			cells[neighbour] = true
			queue.append(neighbour)
			minimum.x = mini(minimum.x, neighbour.x)
			minimum.y = mini(minimum.y, neighbour.y)
			maximum.x = maxi(maximum.x, neighbour.x)
			maximum.y = maxi(maximum.y, neighbour.y)
	result["contours"] = _trace_contours(cells, raster_size)
	result["bounds"] = Rect2(Vector2(minimum * raster_size), Vector2((maximum - minimum + Vector2i.ONE) * raster_size))
	result["area"] = float(cells.size() * raster_size * raster_size)
	return result


static func point_is_inside(region: Dictionary, point: Vector2, clearance: float = 0.0) -> bool:
	var cells: Dictionary = region.get("cells", {}) as Dictionary
	var raster_size: int = int(region.get("raster_size", RASTER_SIZE))
	if cells.is_empty() or not cells.has(_cell_at(point, raster_size)):
		return false
	if clearance <= 0.0:
		return true
	# Only a small local square is queried, independent of arena area.
	var minimum: Vector2i = _cell_at(point - Vector2.ONE * clearance, raster_size)
	var maximum: Vector2i = _cell_at(point + Vector2.ONE * clearance, raster_size)
	var squared_clearance: float = clearance * clearance
	for row: int in range(minimum.y, maximum.y + 1):
		for column: int in range(minimum.x, maximum.x + 1):
			var cell: Vector2i = Vector2i(column, row)
			if cells.has(cell):
				continue
			var top_left: Vector2 = Vector2(cell * raster_size)
			var nearest: Vector2 = point.clamp(top_left, top_left + Vector2.ONE * raster_size)
			if nearest.distance_squared_to(point) < squared_clearance - 0.0001:
				return false
	return true


static func closest_allowed_point(region: Dictionary, point: Vector2, clearance: float = 9.0, origin: Vector2 = Vector2.INF) -> Vector2:
	# Runtime callers should retain the last valid position and provide it here.
	# Sweeping from it avoids moving through a forbidden gap to land on safe ground.
	if origin.is_finite() and point_is_inside(region, origin, clearance):
		return clamp_motion(region, origin, point, clearance)
	if point_is_inside(region, point, clearance):
		return point
	var cells: Dictionary = region.get("cells", {}) as Dictionary
	if cells.is_empty():
		return region.get("center", point) as Vector2
	var raster_size: int = int(region.get("raster_size", RASTER_SIZE))
	var nearest_point: Vector2 = region.get("center", point) as Vector2
	var nearest_distance: float = INF
	# Exceptional recovery only (initial placement or an externally teleported body).
	# Normal movement uses the bounded local sweep above, never this region scan.
	for cell: Vector2i in cells:
		var candidate: Vector2 = Vector2(cell * raster_size) + Vector2.ONE * float(raster_size) * 0.5
		var squared_distance: float = candidate.distance_squared_to(point)
		if squared_distance >= nearest_distance or not point_is_inside(region, candidate, clearance):
			continue
		nearest_distance = squared_distance
		nearest_point = candidate
	if nearest_distance < INF:
		return nearest_point
	# A corridor narrower than the body cannot supply the requested clearance.
	# Still return actual floor, rather than a point in water or outside the map.
	for cell: Vector2i in cells:
		var candidate: Vector2 = Vector2(cell * raster_size) + Vector2.ONE * float(raster_size) * 0.5
		var squared_distance: float = candidate.distance_squared_to(point)
		if squared_distance < nearest_distance:
			nearest_distance = squared_distance
			nearest_point = candidate
	return nearest_point


static func clamp_motion(region: Dictionary, origin: Vector2, target: Vector2, clearance: float = 9.0) -> Vector2:
	var start: Vector2 = origin
	if not point_is_inside(region, start, clearance):
		start = closest_allowed_point(region, start, clearance)
		if not point_is_inside(region, start, clearance):
			return start
	var movement: Vector2 = target - start
	var raster_size: int = int(region.get("raster_size", RASTER_SIZE))
	var steps: int = maxi(1, ceili(movement.length() / (float(raster_size) * 0.5)))
	var previous_t: float = 0.0
	for index: int in range(1, steps + 1):
		var current_t: float = float(index) / float(steps)
		if point_is_inside(region, start + movement * current_t, clearance):
			previous_t = current_t
			continue
		var low: float = previous_t
		var high: float = current_t
		for refinement: int in range(10):
			var middle: float = (low + high) * 0.5
			if point_is_inside(region, start + movement * middle, clearance):
				low = middle
			else:
				high = middle
		return start + movement * low
	return target


static func _cell_at(point: Vector2, raster_size: int) -> Vector2i:
	return Vector2i(floori(point.x / float(raster_size)), floori(point.y / float(raster_size)))


static func _cell_is_allowed(cell: Vector2i, center: Vector2, radius: float, allowed: Dictionary, terrain_size: int, raster_size: int) -> bool:
	var top_left: Vector2 = Vector2(cell * raster_size)
	var bottom_right: Vector2 = top_left + Vector2.ONE * raster_size
	# The complete raster cell must fit in the disk; it never extends the radius.
	var farthest: Vector2 = Vector2(maxf(absf(top_left.x - center.x), absf(bottom_right.x - center.x)), maxf(absf(top_left.y - center.y), absf(bottom_right.y - center.y)))
	if farthest.length_squared() > radius * radius:
		return false
	# Sampling both extrema also handles an authored grid not divisible by four.
	var minimum: Vector2i = _cell_at(top_left, terrain_size)
	var maximum: Vector2i = _cell_at(bottom_right - Vector2.ONE * 0.001, terrain_size)
	for row: int in range(minimum.y, maximum.y + 1):
		for column: int in range(minimum.x, maximum.x + 1):
			if not allowed.has(Vector2i(column, row)):
				return false
	return true


static func _trace_contours(cells: Dictionary, raster_size: int) -> Array[PackedVector2Array]:
	# Directed edges keep filled terrain on their right. Outer contours and holes
	# consequently have opposite winding and can both become collision segments.
	var edges: Dictionary = {}
	for cell: Vector2i in cells:
		if not cells.has(cell + Vector2i.UP):
			_add_edge(edges, cell, 0)
		if not cells.has(cell + Vector2i.RIGHT):
			_add_edge(edges, cell + Vector2i.RIGHT, 1)
		if not cells.has(cell + Vector2i.DOWN):
			_add_edge(edges, cell + Vector2i.ONE, 2)
		if not cells.has(cell + Vector2i.LEFT):
			_add_edge(edges, cell + Vector2i.DOWN, 3)
	var contours: Array[PackedVector2Array] = []
	while not edges.is_empty():
		var start: Vector2i = edges.keys()[0] as Vector2i
		var vertex: Vector2i = start
		var direction: int = _first_direction(int(edges[start]))
		var vertices: Array[Vector2i] = []
		var closed: bool = false
		while edges.has(vertex):
			vertices.append(vertex)
			_remove_edge(edges, vertex, direction)
			vertex += CARDINALS[direction]
			if vertex == start:
				closed = true
				break
			if not edges.has(vertex):
				break
			# At a diagonal contact, turn right first to preserve separate loops.
			var available: int = int(edges[vertex])
			var next_direction: int = -1
			for turn: int in [1, 0, 3, 2]:
				var option: int = (direction + turn) % 4
				if available & (1 << option):
					next_direction = option
					break
			if next_direction < 0:
				break
			direction = next_direction
		if closed and vertices.size() >= 3:
			var contour: PackedVector2Array = _simplify_contour(vertices, raster_size)
			if contour.size() >= 3:
				contours.append(contour)
	return contours


static func _add_edge(edges: Dictionary, vertex: Vector2i, direction: int) -> void:
	edges[vertex] = int(edges.get(vertex, 0)) | (1 << direction)


static func _remove_edge(edges: Dictionary, vertex: Vector2i, direction: int) -> void:
	var remaining: int = int(edges[vertex]) & ~(1 << direction)
	if remaining == 0:
		edges.erase(vertex)
	else:
		edges[vertex] = remaining


static func _first_direction(mask: int) -> int:
	for direction: int in range(4):
		if mask & (1 << direction):
			return direction
	return 0


static func _simplify_contour(vertices: Array[Vector2i], raster_size: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for index: int in range(vertices.size()):
		var previous: Vector2i = vertices[posmod(index - 1, vertices.size())]
		var current: Vector2i = vertices[index]
		var following: Vector2i = vertices[(index + 1) % vertices.size()]
		var incoming: Vector2i = current - previous
		var outgoing: Vector2i = following - current
		if incoming.x * outgoing.y - incoming.y * outgoing.x != 0:
			result.append(Vector2(current * raster_size))
	return result
