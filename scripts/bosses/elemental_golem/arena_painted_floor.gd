extends RefCounted
## Reconcile the redesigned three-row arena with its older gameplay mask in memory.
const NEIGHBORS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func reconcile(cells: Dictionary[Vector2i, int], layers: Array, definitions: Dictionary,
		textures: RefCounted, grid: int, grid_offset: Vector2) -> bool:
	var painted: Dictionary[Vector2i, bool] = {}
	for layer: Dictionary in layers:
		if str(layer.get("__identifier", "")) != "Floor_Elemental" or not bool(layer.get("visible", true)): continue
		var definition: Dictionary = definitions.get(int(layer.get("__tilesetDefUid", -1)), {}) as Dictionary
		var image: Image = textures.call("get_source_image", str(definition.get("relPath", ""))) as Image
		if image == null: return false
		var size: int = int(layer.__gridSize)
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0))) - grid_offset
		for tile: Dictionary in layer.get("gridTiles", []):
			var half: int = floori(float(size) * 0.5)
			var flip: int = int(tile.get("f", 0))
			var pixel: Vector2i = Vector2i(int(tile.src[0]) + (size - 1 - half if flip & 1 else half),
				int(tile.src[1]) + (size - 1 - half if flip & 2 else half))
			# A transparent chamfer is void, even if its tile cell is painted.
			if pixel.x >= image.get_width() or pixel.y >= image.get_height() or image.get_pixelv(pixel).a < 0.5: continue
			var cell: Vector2i = Vector2i((Vector2(float(tile.px[0]), float(tile.px[1])) + offset) / float(grid))
			painted[cell] = true
	if painted.is_empty(): return false
	var difference: int = 0
	var total: int = painted.size()
	for cell: Vector2i in cells:
		var value: int = cells[cell]
		var supported: bool = value == 3 or (value >= 11 and value <= 19)
		if supported and not painted.has(cell): total += 1
		if supported != painted.has(cell): difference += 1
	# Small edits still use explicit IntGrid rules. This only repairs a wholesale redraw.
	if float(difference) / float(total) < 0.25: return false
	var components: Array[Dictionary] = _components(painted)
	var middle: Dictionary = {}
	var left: Array[Dictionary] = []
	var right: Array[Dictionary] = []
	for component: Dictionary in components:
		if middle.is_empty() or int(component.count) > int(middle.count): middle = component
	var center: float = (middle.area as Rect2i).get_center().x
	for component: Dictionary in components:
		if component == middle: continue
		if (component.area as Rect2i).get_center().x < center: left.append(component)
		else: right.append(component)
	if left.size() != 3 or right.size() != 3: return false
	left.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.area as Rect2i).position.y < (b.area as Rect2i).position.y)
	right.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.area as Rect2i).position.y < (b.area as Rect2i).position.y)
	var centers: Array[float] = []
	var hall_start: int = 0
	for row: int in range(3):
		centers.append(((left[row].area as Rect2i).get_center().y + (right[row].area as Rect2i).get_center().y) * 0.5)
		hall_start = maxi(hall_start, maxi((left[row].area as Rect2i).end.y, (right[row].area as Rect2i).end.y))
	for cell: Vector2i in cells:
		if cells[cell] != 2: cells[cell] = 1
	for row: int in range(3):
		for cell: Vector2i in left[row].cells: cells[cell] = 11 + row * 3
		for cell: Vector2i in right[row].cells: cells[cell] = 13 + row * 3
	for cell: Vector2i in middle.cells:
		var row: int = 0 if cell.y < (centers[0] + centers[1]) * 0.5 else 1 if cell.y < (centers[1] + centers[2]) * 0.5 else 2
		cells[cell] = 3 if cell.y >= hall_start else 12 + row * 3
	return true


static func _components(painted: Dictionary[Vector2i, bool]) -> Array[Dictionary]:
	var remaining: Dictionary[Vector2i, bool] = painted.duplicate()
	var result: Array[Dictionary] = []
	while not remaining.is_empty():
		var first: Vector2i = remaining.keys()[0]
		var queue: Array[Vector2i] = [first]
		var area: Rect2i = Rect2i(first, Vector2i.ONE)
		remaining.erase(first)
		var cursor: int = 0
		while cursor < queue.size():
			var cell: Vector2i = queue[cursor]
			cursor += 1
			area = area.merge(Rect2i(cell, Vector2i.ONE))
			for direction: Vector2i in NEIGHBORS:
				var neighbor: Vector2i = cell + direction
				if not remaining.has(neighbor): continue
				remaining.erase(neighbor)
				queue.append(neighbor)
		result.append({"cells": queue, "area": area, "count": queue.size()})
	return result
