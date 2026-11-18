extends RefCounted
## Shared flow field sampled from actual floor and static collision footprints.
const CELL: float = 8.0
const RADIUS: float = 7.5
const STEPS: Array[Vector2i] = [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]
var cells: Dictionary[Vector2i, bool] = {}
var distances: Dictionary[Vector2i, int] = {}
var density: Dictionary[Vector2i, int] = {}
var owner: Node2D
var floor_query: Callable
var shape: CircleShape2D = CircleShape2D.new()
var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var goal: Vector2i
var sampling_done: bool = false
var _sample_rect: Rect2i
var _sample_index: int = 0
var _flow_goal: Vector2i
var _flow_distances: Dictionary[Vector2i, int] = {}
var _flow_queue: Array[Vector2i] = []
var _flow_index: int = 0
var flow_building: bool:
	get:
		return not _flow_queue.is_empty()


func configure(bounds: Rect2, encounter: Node2D, floor_test: Callable) -> void:
	owner = encounter
	floor_query = floor_test
	shape.radius = RADIUS
	query.shape = shape
	query.collision_mask = 1
	var first: Vector2i = cell(bounds.position)
	_sample_rect = Rect2i(first, cell(bounds.end) - first + Vector2i.ONE)
	_sample_index = 0
	sampling_done = false
	cells.clear()
	distances.clear()
	_flow_queue.clear()


func sample_cells(deadline_usec: int = 0) -> void:
	if sampling_done:
		return
	var space: PhysicsDirectSpaceState2D = owner.get_world_2d().direct_space_state
	var count: int = _sample_rect.get_area()
	while _sample_index < count:
		if deadline_usec > 0 and _sample_index % 8 == 0 and Time.get_ticks_usec() >= deadline_usec:
			return
		@warning_ignore("integer_division")
		var coord: Vector2i = _sample_rect.position + Vector2i(_sample_index % _sample_rect.size.x, _sample_index / _sample_rect.size.x)
		_sample_index += 1
		var point: Vector2 = center(coord)
		if has_floor(point):
			query.transform = Transform2D(0.0, owner.to_global(point))
			if space.intersect_shape(query, 1).is_empty():
				cells[coord] = true
	sampling_done = true


func cell(point: Vector2) -> Vector2i:
	return Vector2i((point / CELL).floor())


func center(coord: Vector2i) -> Vector2:
	return (Vector2(coord) + Vector2.ONE * 0.5) * CELL


func has_floor(point: Vector2) -> bool:
	if not bool(floor_query.call(owner.to_global(point))):
		return false
	for step: Vector2i in STEPS:
		if not bool(floor_query.call(owner.to_global(point + Vector2(step).normalized() * RADIUS))):
			return false
	return true


func update_target(target: Vector2, deadline_usec: int = 0) -> void:
	if not sampling_done or cells.is_empty():
		return
	if _flow_queue.is_empty():
		var nearest: Vector2i = _nearest_cell(target)
		if not cells.has(nearest) or (nearest == goal and not distances.is_empty()):
			return
		_flow_goal = nearest
		_flow_distances = {nearest: 0}
		_flow_queue.append(nearest)
		_flow_index = 0
	while _flow_index < _flow_queue.size():
		if deadline_usec > 0 and _flow_index % 16 == 0 and Time.get_ticks_usec() >= deadline_usec:
			return
		var coord: Vector2i = _flow_queue[_flow_index]
		_flow_index += 1
		for step: Vector2i in STEPS:
			var next: Vector2i = coord + step
			if _flow_distances.has(next) or not connected(coord, step):
				continue
			_flow_distances[next] = _flow_distances[coord] + 1
			_flow_queue.append(next)
	# Keep steering against the last complete field until the replacement is ready.
	goal = _flow_goal
	distances = _flow_distances
	_flow_queue.clear()


func _nearest_cell(target: Vector2) -> Vector2i:
	var target_cell: Vector2i = cell(target)
	if cells.has(target_cell):
		return target_cell
	# Nox can reach positions with less clearance than a monster requires.
	var closest: Vector2i = target_cell
	var best: float = INF
	for y: int in range(-4, 5):
		for x: int in range(-4, 5):
			var candidate: Vector2i = target_cell + Vector2i(x, y)
			if cells.has(candidate):
				var distance: float = center(candidate).distance_squared_to(target)
				if distance < best:
					closest = candidate
					best = distance
	if best == INF:
		# Keep a usable goal even if Nox is beyond the nearby walkable cells.
		for candidate: Vector2i in cells:
			var distance: float = center(candidate).distance_squared_to(target)
			if distance < best:
				closest = candidate
				best = distance
	return closest


func connected(coord: Vector2i, step: Vector2i) -> bool:
	return cells.has(coord + step) and (step.x == 0 or step.y == 0 or
		(cells.has(coord + Vector2i(step.x, 0)) and cells.has(coord + Vector2i(0, step.y))))


func can_enter(origin: Vector2, _target: Vector2) -> bool:
	var coord: Vector2i = cell(origin)
	if not distances.has(coord):
		return false
	# Prefer nearby approaches over a distant detour to another river crossing.
	var direct: float = origin.distance_to(center(goal))
	return float(distances[coord]) * CELL <= direct * 1.6 + 32.0


func update_crowd(actors: Array[Node2D]) -> void:
	density.clear()
	for actor: Node2D in actors:
		var coord: Vector2i = cell(actor.position)
		density[coord] = density.get(coord, 0) + 1


func waypoint(origin: Vector2, _target: Vector2) -> Vector2:
	var coord: Vector2i = cell(origin)
	var best: float = float(distances.get(coord, 1000000))
	var result: Vector2 = center(coord)
	for step: Vector2i in STEPS:
		var next: Vector2i = coord + step
		if not connected(coord, step) or not distances.has(next):
			continue
		var score: float = float(distances[next]) + minf(float(density.get(next, 0)) * 0.30, 0.75)
		if score < best:
			best = score
			result = center(next)
	return result


func can_move(origin: Vector2, motion: Vector2) -> bool:
	var end: Vector2 = origin + motion
	if not cells.has(cell(end)) or not has_floor(end):
		return false
	query.transform = Transform2D(0.0, owner.to_global(origin))
	query.motion = owner.global_transform.basis_xform(motion)
	var fractions: PackedFloat32Array = owner.get_world_2d().direct_space_state.cast_motion(query)
	query.motion = Vector2.ZERO
	return fractions[0] >= 0.999


func steer(origin: Vector2, desired: Vector2) -> Vector2:
	if desired.is_zero_approx():
		return Vector2.ZERO
	var length: float = desired.length()
	var ahead: Vector2 = desired.normalized() * 12.0
	if can_move(origin, ahead):
		return desired
	var fallback: Vector2 = (waypoint(origin, Vector2.ZERO) - origin).limit_length(10.0)
	if can_move(origin, fallback):
		return fallback.normalized() * length
	return Vector2.ZERO
