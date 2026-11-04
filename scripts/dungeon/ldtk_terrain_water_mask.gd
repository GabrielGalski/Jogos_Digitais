extends RefCounted
## Load-time coastline cutout. Logical support remains independent of art alpha.

const GRID: int = 16
const EDGE_LAYERS: Array[String] = ["TerrainFaces", "TerrainCliffRim", "WaterBanks"]


static func replacement_cells(layers: Array) -> Dictionary:
	var cells: Dictionary = {}
	for layer: Dictionary in layers:
		var name: String = str(layer.get("__identifier", ""))
		if name not in ["TerrainCliffRim", "WaterBanks"] or not bool(layer.get("visible", true)):
			continue
		var offset_x: int = int(layer.get("__pxTotalOffsetX", 0))
		var offset_y: int = int(layer.get("__pxTotalOffsetY", 0)) if name == "WaterBanks" else 0
		# This layer already projects the contour upward; its raw Y is the support row.
		for tile: Dictionary in layer.get("gridTiles", []):
			cells[Vector2i(floori(float(tile.px[0] + offset_x) / GRID), floori(float(tile.px[1] + offset_y) / GRID))] = true
	return cells


static func _local_rect(area: Rect2, origin: Rect2, size: Vector2i) -> Rect2i:
	var overlap: Rect2 = area.intersection(origin)
	if not overlap.has_area():
		return Rect2i()
	var first: Vector2i = Vector2i((overlap.position - origin.position).floor())
	var ending: Vector2i = Vector2i((overlap.end - origin.position).ceil())
	return Rect2i(first, ending - first).intersection(Rect2i(Vector2i.ZERO, size))


static func _seal_cliff_joints(mask: Image, cliff: Image, floor_image: Image, faces: Array[Rect2i]) -> void:
	var extent: Rect2i = Rect2i(Vector2i.ZERO, mask.get_size())
	for face: Rect2i in faces:
		# The neighbouring rim and face can each have transparent edge pixels.
		# Seal only the space between existing terrain pixels, never past the
		# outer rock silhouette or along unrelated river banks.
		var strip: Rect2i = Rect2i(face.position - Vector2i(GRID, 0), face.size + Vector2i(GRID * 2, 0)).intersection(extent)
		for y: int in range(strip.position.y, strip.end.y):
			var first: int = -1
			var last: int = -1
			for x: int in range(strip.position.x, strip.end.x):
				if cliff.get_pixel(x, y).r > 0.5 or floor_image.get_pixel(x, y).r > 0.5:
					if first < 0: first = x
					last = x
			if first >= 0 and last > first:
				mask.fill_rect(Rect2i(first, y, last - first + 1, 1), Color.TRANSPARENT)


static func build(rect: Rect2, floor_cells: Dictionary, layers: Array, definitions: Dictionary, textures: RefCounted, height_at: Callable) -> ImageTexture:
	var size: Vector2i = Vector2i(ceili(rect.size.x), ceili(rect.size.y))
	# LA8 stores luminance + alpha: two bytes per pixel, nearest, no mipmaps.
	var mask: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_LA8)
	mask.fill(Color.WHITE)
	var projected_floor: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_L8)
	projected_floor.fill(Color.BLACK)
	var replaced: Dictionary = replacement_cells(layers)
	for cell: Vector2i in floor_cells:
		var area: Rect2 = Rect2(Vector2(cell * GRID), Vector2.ONE * GRID)
		mask.fill_rect(_local_rect(area, rect, size), Color.TRANSPARENT)
		if replaced.has(cell):
			continue
		var height: int = roundi(float(height_at.call(area.get_center()))) if height_at.is_valid() else 0
		area.position.y -= height
		projected_floor.fill_rect(_local_rect(area, rect, size), Color.WHITE)
	var opaque_cliff: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_L8)
	opaque_cliff.fill(Color.BLACK)
	var coast_rects: Array[Rect2i] = []
	var face_rects: Array[Rect2i] = []
	var projection: int = 0
	for layer: Dictionary in layers:
		if str(layer.get("__identifier", "")) == "TerrainCliffRim" and bool(layer.get("visible", true)):
			projection = maxi(projection, -int(layer.get("__pxTotalOffsetY", 0)))
	for layer: Dictionary in layers:
		var is_bank: bool = str(layer.get("__identifier", "")) == "WaterBanks"
		if str(layer.get("__identifier", "")) not in EDGE_LAYERS or not bool(layer.get("visible", true)):
			continue
		var definition: Dictionary = definitions.get(int(layer.get("__tilesetDefUid", -1)), {}) as Dictionary
		var source: Image = textures.call("get_source_image", str(definition.get("relPath", ""))) as Image
		if source == null:
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for tile: Dictionary in layer.get("gridTiles", []):
			var point: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1])) + offset
			var bounds: Rect2i = _local_rect(Rect2(point, Vector2.ONE * GRID), rect, size)
			if not bounds.has_area():
				continue
			if str(layer.get("__identifier", "")) == "TerrainFaces":
				face_rects.append(bounds)
			var foot: Vector2i = Vector2i(((point + Vector2(8, 8 if is_bank else projection + 8)) / GRID).floor())
			# Only the water-facing contour may reveal water through the atlas alpha.
			# Interior front faces retain logical clipping, including their soft base.
			if is_bank or not floor_cells.has(foot) or not floor_cells.has(foot + Vector2i.RIGHT) or not floor_cells.has(foot + Vector2i.DOWN):
				coast_rects.append(bounds)
			var source_point: Vector2i = Vector2i(int(tile.src[0]), int(tile.src[1]))
			var flip: int = int(tile.get("f", 0))
			var opacity: float = float(tile.get("a", 1.0)) * float(layer.get("__opacity", 1.0))
			for y: int in range(bounds.position.y, bounds.end.y):
				for x: int in range(bounds.position.x, bounds.end.x):
					var local: Vector2i = Vector2i(Vector2(x, y) + rect.position - point)
					if (flip & 1) != 0: local.x = GRID - 1 - local.x
					if (flip & 2) != 0: local.y = GRID - 1 - local.y
					if source.get_pixelv(source_point + local).a * opacity >= 0.5:
						opaque_cliff.set_pixel(x, y, Color.WHITE)
	for bounds: Rect2i in coast_rects:
		for y: int in range(bounds.position.y, bounds.end.y):
			for x: int in range(bounds.position.x, bounds.end.x):
				var hidden: bool = projected_floor.get_pixel(x, y).r > 0.5 or opaque_cliff.get_pixel(x, y).r > 0.5
				mask.set_pixel(x, y, Color.TRANSPARENT if hidden else Color.WHITE)
	_seal_cliff_joints(mask, opaque_cliff, projected_floor, face_rects)
	return ImageTexture.create_from_image(mask)
