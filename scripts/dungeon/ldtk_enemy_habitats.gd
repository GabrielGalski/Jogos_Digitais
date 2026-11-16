extends RefCounted
## Read-only habitat queries from the composed castle floor, curved river and bridge decks.
const BANK_REACH: float = 112.0
const DRY_MARGIN: float = 10.0
var castle_cells: Dictionary[Vector2i, bool] = {}
var castle_bounds: Rect2 = Rect2()
var river: RefCounted = null
var river_bounds: Rect2 = Rect2()
var arena: Node2D = null
var ground_query: Callable = Callable()
var height_query: Callable = Callable()


func configure(world: Node2D, layers: Array, contour: RefCounted, ground: Callable, height: Callable) -> void:
	arena = world
	river = contour
	ground_query = ground
	height_query = height
	if river != null: river_bounds = river.get("bounds") as Rect2
	for layer: Dictionary in layers:
		# The castle's decorative tile layer is currently hidden; its authored footprint
		# still identifies the upper plateau without changing the map's appearance.
		if str(layer.get("__identifier", "")) != "Floor_Castle": continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		var tiles: Array = (layer.get("gridTiles", []) as Array).duplicate()
		tiles.append_array(layer.get("autoLayerTiles", []))
		for tile: Dictionary in tiles:
			var point: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1])) + offset
			var cell: Vector2i = Vector2i((point / 16.0).floor())
			castle_cells[cell] = true
			var rect: Rect2 = Rect2(point, Vector2.ONE * 16.0)
			castle_bounds = rect if castle_bounds.size.is_zero_approx() else castle_bounds.merge(rect)


func is_castle(point: Vector2) -> bool:
	return castle_cells.has(Vector2i((arena.to_local(point) / 16.0).floor())) and bool(ground_query.call(point))


func castle_zone(rect: Rect2) -> bool:
	return Rect2(arena.to_global(castle_bounds.position), castle_bounds.size).intersects(rect)


func is_bridge(point: Vector2) -> bool:
	return river != null and bool(river.call("in_bridge", arena.to_local(point)))


func is_water(point: Vector2) -> bool:
	if river == null: return false
	var local: Vector2 = arena.to_local(point)
	if not river_bounds.has_point(local) or is_bridge(point): return false
	var banks: Vector4 = river.call("banks_at", local.y) as Vector4
	return banks.w > 0.5 and local.x > banks.x and local.x < banks.y


func slime_support(point: Vector2) -> bool:
	if river == null: return false
	var local: Vector2 = arena.to_local(point)
	if local.y < river_bounds.position.y + 16.0 or local.y >= river_bounds.end.y - 16.0: return false
	var banks: Vector4 = river.call("banks_at", local.y) as Vector4
	if banks.w < 0.5 or local.x < banks.x - BANK_REACH or local.x > banks.y + BANK_REACH: return false
	# No Slimes on the elevated left bank beside the upper castle.
	if local.x < banks.x and float(height_query.call(point)) > 12.0: return false
	if not is_bridge(point) and local.x > banks.x - DRY_MARGIN and local.x < banks.y + DRY_MARGIN: return false
	return bool(ground_query.call(point))


func slime_height(point: Vector2) -> float:
	return float(height_query.call(point))


func slime_zone(rect: Rect2) -> bool:
	return river != null and Rect2(arena.to_global(river_bounds.position), river_bounds.size).grow(BANK_REACH).intersects(rect)


func slime_weight(point: Vector2) -> float:
	# One fifth of the bank/river acceptance rate on bridge decking and its ends.
	if river != null:
		for deck: Rect2 in river.get("bridges") as Array:
			if deck.grow(16.0).has_point(arena.to_local(point)): return 0.20
		var local: Vector2 = arena.to_local(point)
		var banks: Vector4 = river.call("banks_at", local.y) as Vector4
		if local.x < banks.x: return 0.35
	return 1.0


func slime_cells() -> Dictionary:
	var result: Dictionary = {}
	if river == null: return result
	var area: Rect2 = river_bounds.grow(BANK_REACH)
	var first: Vector2i = Vector2i((area.position / 16.0).floor())
	var ending: Vector2i = Vector2i((area.end / 16.0).ceil())
	for y: int in range(first.y, ending.y):
		for x: int in range(first.x, ending.x):
			var cell: Vector2i = Vector2i(x, y)
			if slime_support(arena.to_global(Vector2(cell * 16) + Vector2.ONE * 8.0)): result[cell] = true
	return result
