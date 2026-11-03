extends RefCounted
## Open A*: terrain never blocks spirits. Crowd occupancy is a soft routing cost.
const CELL: float = 24.0
var grid: AStarGrid2D = AStarGrid2D.new()
var _weighted_cells: Array[Vector2i] = []


func configure(bounds: Rect2) -> void:
	var corner: Vector2i = cell(bounds.position)
	var ending: Vector2i = cell(bounds.end) + Vector2i.ONE
	grid.region = Rect2i(corner, ending - corner)
	grid.cell_size = Vector2.ONE * CELL
	grid.offset = Vector2.ONE * CELL * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()


func cell(point: Vector2) -> Vector2i:
	return Vector2i((point / CELL).floor())


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
	if origin.distance_squared_to(target) < 72.0 * 72.0:
		return target
	var start: Vector2i = cell(origin)
	var goal: Vector2i = cell(target)
	if not grid.region.has_point(start) or not grid.region.has_point(goal):
		return target
	var path: Array[Vector2i] = grid.get_id_path(start, goal)
	if path.size() < 3:
		return target
	return grid.get_point_position(path[mini(2, path.size() - 1)])
