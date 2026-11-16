extends RefCounted
## Crowd-aware routing. Ground hordes use authored walkable cells.
const CELL: float = 24.0
var grid: AStarGrid2D = AStarGrid2D.new()
var _weighted_cells: Array[Vector2i] = []


var grounded: bool = false
var cell_size: float = CELL


func configure(bounds: Rect2, walkable: Dictionary = {}) -> void:
	grounded = not walkable.is_empty()
	cell_size = 16.0 if grounded else CELL
	var corner: Vector2i = cell(bounds.position)
	var ending: Vector2i = cell(bounds.end) + Vector2i.ONE
	grid.region = Rect2i(corner, ending - corner)
	grid.cell_size = Vector2.ONE * cell_size
	grid.offset = Vector2.ONE * cell_size * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES if grounded else AStarGrid2D.DIAGONAL_MODE_ALWAYS
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	if grounded:
		grid.fill_solid_region(grid.region)
		for coord: Vector2i in walkable:
			if grid.region.has_point(coord):
				grid.set_point_solid(coord, false)


func cell(point: Vector2) -> Vector2i:
	return Vector2i((point / cell_size).floor())


func can_enter(origin: Vector2, target: Vector2) -> bool:
	if not grounded:
		return true
	var start: Vector2i = cell(origin)
	var goal: Vector2i = cell(target)
	return grid.region.has_point(start) and grid.region.has_point(goal) and not grid.is_point_solid(start) and not grid.get_id_path(start, goal).is_empty()


func update_crowd(actors: Array[Node2D]) -> void:
	for coordinate: Vector2i in _weighted_cells:
		grid.set_point_weight_scale(coordinate, 1.0)
	_weighted_cells.clear()
	var counts: Dictionary[Vector2i, int] = {}
	for actor: Node2D in actors:
		var coordinate: Vector2i = cell(actor.position)
		if grid.region.has_point(coordinate):
			counts[coordinate] = counts.get(coordinate, 0) + 1
	for coordinate: Vector2i in counts:
		grid.set_point_weight_scale(coordinate, 1.0 + minf(counts[coordinate] * 0.45, 2.25))
		_weighted_cells.append(coordinate)


func waypoint(origin: Vector2, target: Vector2) -> Vector2:
	if not grounded and origin.distance_squared_to(target) < 72.0 * 72.0:
		return target
	var start: Vector2i = cell(origin)
	var goal: Vector2i = cell(target)
	if not grid.region.has_point(start) or not grid.region.has_point(goal):
		return target
	var path: Array[Vector2i] = grid.get_id_path(start, goal)
	if grounded and path.size() >= 2:
		return grid.get_point_position(path[1])
	if path.size() < 3:
		return target
	return grid.get_point_position(path[mini(2, path.size() - 1)])
