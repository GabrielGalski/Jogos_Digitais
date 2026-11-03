extends RefCounted
## Exact local distance to merged coast rectangles, with nearest-coast attributes.
## RGBA16F = distance in world px, foam gain, shallow width multiplier, raised shadow.

const CELL_SIZE: int = 4
const CHUNK_SIZE: int = 256
const SAMPLE_SIZE: int = 2
const COAST: Script = preload("res://scripts/visual/water_coast.gd")
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var _coasts: Dictionary = {}
var _reach: float = 0.0
var _padding: int = 0
var _open_water: ImageTexture = null


func configure(solid_cells: Dictionary, reach: float, shore_styles: Dictionary = {}, overrides: Array[Dictionary] = []) -> void:
	_coasts.clear()
	_reach = reach
	_padding = ceili((reach + CELL_SIZE) / SAMPLE_SIZE) * SAMPLE_SIZE
	var cells_by_chunk: Dictionary = {}
	for cell: Vector2i in solid_cells:
		var exposed: bool = false
		for direction: Vector2i in SIDES:
			if not solid_cells.has(cell + direction):
				exposed = true
				break
		if not exposed:
			continue
		var chunk: Vector2i = Vector2i((Vector2(cell * CELL_SIZE) / CHUNK_SIZE).floor())
		if not cells_by_chunk.has(chunk):
			cells_by_chunk[chunk] = {}
		var kind: int = COAST.style_at(Vector2(cell * CELL_SIZE) + Vector2.ONE * 2.0, int(shore_styles.get(cell, 0)), overrides)
		(cells_by_chunk[chunk] as Dictionary)[cell] = kind
	for chunk: Vector2i in cells_by_chunk:
		_coasts[chunk] = _merge_cells(cells_by_chunk[chunk])
	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBAF)
	image.fill(Color(reach + CELL_SIZE, 0, 1, 0))
	image.convert(Image.FORMAT_RGBAH)
	_open_water = ImageTexture.create_from_image(image)


func _merge_cells(cells: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rows: Dictionary = {}
	for cell: Vector2i in cells:
		if not rows.has(cell.y):
			rows[cell.y] = []
		(rows[cell.y] as Array).append(cell.x)
	var sorted_rows: Array = rows.keys()
	sorted_rows.sort()
	var previous: Dictionary = {}
	var previous_y: int = -2147483647
	for y: int in sorted_rows:
		if y != previous_y + 1:
			previous.clear()
		previous_y = y
		var current: Dictionary = {}
		var xs: Array = rows[y]
		xs.sort()
		var cursor: int = 0
		while cursor < xs.size():
			var start: int = int(xs[cursor])
			var end: int = start + 1
			var kind: int = int(cells[Vector2i(start, y)])
			cursor += 1
			while cursor < xs.size() and int(xs[cursor]) == end and int(cells[Vector2i(end, y)]) == kind:
				end += 1
				cursor += 1
			var key: Vector3i = Vector3i(start, end - start, kind)
			var index: int = int(previous.get(key, -1))
			if index >= 0:
				var rect: Rect2 = result[index].rect
				rect.size.y += CELL_SIZE
				result[index]["rect"] = rect
			else:
				index = result.size()
				result.append({"rect": Rect2(start * CELL_SIZE, y * CELL_SIZE, (end - start) * CELL_SIZE, CELL_SIZE),
					"appearance": COAST.APPEARANCE[kind]})
			current[key] = index
		previous = current
	return result


func build_chunk(coordinate: Vector2i) -> Dictionary:
	var coast_rects: Array[Dictionary] = []
	var world_rect: Rect2 = Rect2(Vector2(coordinate * CHUNK_SIZE), Vector2(CHUNK_SIZE, CHUNK_SIZE)).grow(_padding + _reach)
	for y: int in range(coordinate.y - 1, coordinate.y + 2):
		for x: int in range(coordinate.x - 1, coordinate.x + 2):
			for coast: Dictionary in _coasts.get(Vector2i(x, y), []):
				if world_rect.intersects(coast.rect):
					coast_rects.append(coast)
	if coast_rects.is_empty():
		return {"texture": _open_water, "padding": _padding, "has_shore": false, "bytes": 8}
	# Stable tie ownership across overlapping fields, independent of query order.
	coast_rects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ar: Rect2 = a.rect
		var br: Rect2 = b.rect
		return ar.position.y < br.position.y if ar.position.y != br.position.y else ar.position.x < br.position.x)
	var size: int = floori(float(CHUNK_SIZE + _padding * 2) / SAMPLE_SIZE)
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(size * size * 4)
	var infinity_squared: float = (_reach + CELL_SIZE) * (_reach + CELL_SIZE)
	for index: int in range(size * size):
		values[index * 4] = infinity_squared
		values[index * 4 + 2] = 1.0
	var origin: Vector2 = Vector2(coordinate * CHUNK_SIZE - Vector2i(_padding, _padding)) + Vector2.ONE
	var reach_squared: float = _reach * _reach
	for coast: Dictionary in coast_rects:
		var rect: Rect2 = coast.rect
		var appearance: Vector3 = coast.appearance
		var first: Vector2i = Vector2i(((rect.position - Vector2.ONE * _reach - origin) / SAMPLE_SIZE).ceil()).max(Vector2i.ZERO)
		var last: Vector2i = Vector2i(((rect.end + Vector2.ONE * _reach - origin) / SAMPLE_SIZE).floor()).min(Vector2i.ONE * (size - 1))
		var dx_squared: PackedFloat32Array = PackedFloat32Array()
		for x: int in range(first.x, last.x + 1):
			var px: float = origin.x + x * SAMPLE_SIZE
			var dx: float = maxf(maxf(rect.position.x - px, px - rect.end.x), 0.0)
			dx_squared.append(dx * dx)
		for y: int in range(first.y, last.y + 1):
			var py: float = origin.y + y * SAMPLE_SIZE
			var dy: float = maxf(maxf(rect.position.y - py, py - rect.end.y), 0.0)
			var at: int = (y * size + first.x) * 4
			for dx2: float in dx_squared:
				var d2: float = dx2 + dy * dy
				if d2 <= reach_squared and d2 < values[at]:
					values[at] = d2
					values[at + 1] = appearance.x
					values[at + 2] = appearance.y
					values[at + 3] = appearance.z
				at += 4
	for index: int in range(size * size):
		var d2: float = values[index * 4]
		values[index * 4] = -1.0 if d2 == 0.0 else sqrt(d2)
	var image: Image = Image.create_from_data(size, size, false, Image.FORMAT_RGBAF, values.to_byte_array())
	image.convert(Image.FORMAT_RGBAH)
	return {"texture": ImageTexture.create_from_image(image), "padding": _padding, "has_shore": true, "bytes": image.get_data_size()}
