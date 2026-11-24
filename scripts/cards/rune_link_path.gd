extends RefCounted
## Finds a terrain route only when placing the second rune.

const CORNERS: Array[Vector2] = [
	Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1),
]

var _world: World2D
var _has_floor: Callable
var _ray: PhysicsRayQueryParameters2D


func _init(world: World2D, floor_query: Callable, player_rid: RID) -> void:
	_world = world
	_has_floor = floor_query
	_ray = PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.ZERO, 1, [player_rid])
	_ray.hit_from_inside = true


func segment_clear(from: Vector2, to: Vector2) -> bool:
	_ray.from = from
	_ray.to = to
	if not from.is_equal_approx(to) and not _world.direct_space_state.intersect_ray(_ray).is_empty():
		return false
	var steps: int = maxi(1, ceili(from.distance_to(to) / 4.0))
	for step: int in range(steps + 1):
		if not bool(_has_floor.call(from.lerp(to, float(step) / float(steps)))):
			return false
	return true


func find(from: Vector2, to: Vector2, search_radius: float) -> PackedVector2Array:
	if segment_clear(from, to):
		return PackedVector2Array([from, to])
	var navigation: EnemyNavigationGrid = EnemyNavigationGrid.new()
	# Include places Nox can walk to before the first rune disarms.
	var extent: Vector2 = Vector2.ONE * (search_radius + navigation.cell_size * 2.0)
	var bounds: Rect2 = Rect2(from - extent, extent * 2.0)
	navigation.build(_world, bounds, 1.0, _ray.collision_mask, _ray.exclude)
	var grid: AStarGrid2D = navigation.grid
	var half_cell: float = navigation.cell_size * 0.4
	for y: int in range(grid.region.size.y):
		for x: int in range(grid.region.size.x):
			var cell: Vector2i = Vector2i(x, y)
			if grid.is_point_solid(cell):
				continue
			var center: Vector2 = grid.get_point_position(cell)
			if not bool(_has_floor.call(center)):
				grid.set_point_solid(cell)
				continue
			for corner: Vector2 in CORNERS:
				if not bool(_has_floor.call(center + corner * half_cell)):
					grid.set_point_solid(cell)
					break
	var start: Vector2i = _reachable_cell(navigation, from)
	var finish: Vector2i = _reachable_cell(navigation, to)
	if start.x < 0 or finish.x < 0:
		return PackedVector2Array()
	var route: PackedVector2Array = grid.get_point_path(start, finish)
	if route.is_empty():
		return route
	route.insert(0, from)
	route.append(to)
	return _remove_unneeded_turns(route)


func _reachable_cell(navigation: EnemyNavigationGrid, point: Vector2) -> Vector2i:
	var at: Vector2i = navigation.cell_at(point)
	var best: Vector2i = Vector2i(-1, -1)
	var closest: float = INF
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var cell: Vector2i = at + Vector2i(x, y)
			if not navigation.grid.is_in_boundsv(cell) or navigation.grid.is_point_solid(cell):
				continue
			var center: Vector2 = navigation.grid.get_point_position(cell)
			var distance: float = point.distance_squared_to(center)
			if distance < closest and segment_clear(point, center):
				best = cell
				closest = distance
	return best


func _remove_unneeded_turns(route: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array([route[0]])
	var index: int = 0
	while index < route.size() - 1:
		var next: int = route.size() - 1
		while next > index and not segment_clear(route[index], route[next]):
			next -= 1
		if next == index:
			return PackedVector2Array()
		result.append(route[next])
		index = next
	return result


static func project(route: PackedVector2Array, height_query: Callable) -> PackedVector2Array:
	var first: Vector2 = route[0]
	var projected: PackedVector2Array = PackedVector2Array([first - Vector2(0, float(height_query.call(first)))])
	for index: int in range(1, route.size()):
		var from: Vector2 = route[index - 1]
		var to: Vector2 = route[index]
		var steps: int = maxi(1, ceili(from.distance_to(to) / 8.0))
		for step: int in range(1, steps + 1):
			var ground: Vector2 = from.lerp(to, float(step) / float(steps))
			var point: Vector2 = ground - Vector2(0, float(height_query.call(ground)))
			var previous: Vector2 = projected[-1]
			if point.is_equal_approx(previous):
				continue
			if projected.size() > 1 and projected[-2].direction_to(previous).is_equal_approx(previous.direction_to(point)):
				projected[-1] = point
			else:
				projected.append(point)
	return projected
