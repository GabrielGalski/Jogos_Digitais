extends RefCounted
## Converts visible terrain alpha into presentation-only water occluders.
## Four world pixels per cell retain small banks without a map-sized texture.

const CELL_SIZE: int = 4
var shore_styles: Dictionary = {}


func opaque_cells(layers: Array, definitions: Dictionary, textures: RefCounted, rendered_floor: Dictionary) -> Dictionary:
	shore_styles.clear()
	var cells: Dictionary = {}
	var samples: Dictionary = {}
	for layer: Dictionary in layers:
		var layer_name: String = str(layer.get("__identifier", ""))
		var is_floor: bool = layer_name == "Floor" or layer_name.begins_with("Floor_")
		if not bool(layer.get("visible", true)) or float(layer.get("__opacity", 1.0)) < 1.0:
			continue
		if not is_floor and layer_name != "PlatformUnderside" and not layer_name.begins_with("Walls"):
			continue
		var definition: Dictionary = definitions.get(int(layer.get("__tilesetDefUid", -1)), {})
		if definition.is_empty():
			continue
		var path: String = str(definition.get("relPath", ""))
		var image: Image = textures.call(&"get_source_image", path) as Image
		if image == null or image.is_empty():
			continue
		var grid: int = int(definition.get("tileGridSize", 16))
		var offset: Vector2i = Vector2i(int(layer.get("__pxTotalOffsetX", 0)), int(layer.get("__pxTotalOffsetY", 0)))
		var tiles: Array = layer.get("autoLayerTiles", []).duplicate()
		tiles.append_array(layer.get("gridTiles", []))
		for tile: Dictionary in tiles:
			if float(tile.get("a", 1.0)) < 1.0:
				continue
			var pixel: Vector2i = Vector2i(int(tile.px[0]), int(tile.px[1]))
			var floor_cell: Vector2i = Vector2i((Vector2(pixel) / 16.0).floor())
			if is_floor and not rendered_floor.has(floor_cell):
				continue
			pixel += offset
			var source: Vector2i = Vector2i(int(tile.src[0]), int(tile.src[1]))
			var flip: int = int(tile.get("f", 0))
			var first: Vector2i = Vector2i((Vector2(pixel) / CELL_SIZE).ceil())
			var last: Vector2i = Vector2i((Vector2(pixel + Vector2i(grid, grid)) / CELL_SIZE).floor())
			for y: int in range(first.y, last.y):
				for x: int in range(first.x, last.x):
					var cell: Vector2i = Vector2i(x, y)
					var local: Vector2i = cell * CELL_SIZE - pixel
					var key: String = "%s:%s:%s:%s:%s" % [path, source, grid, flip, local]
					if not samples.has(key):
						samples[key] = _is_opaque(image, source, local, grid, flip)
					if bool(samples[key]):
						cells[cell] = true
						if layer_name == "PlatformUnderside" or layer_name.begins_with("Walls"):
							shore_styles[cell] = 3 # WaterCoast.Kind.RAISED; only these banks cast contact shadow.
	return cells


func _is_opaque(image: Image, source: Vector2i, local: Vector2i, grid: int, flip: int) -> bool:
	for y: int in range(local.y, local.y + CELL_SIZE):
		for x: int in range(local.x, local.x + CELL_SIZE):
			var sample_at: Vector2i = source + Vector2i(grid - 1 - x if (flip & 1) != 0 else x,
				grid - 1 - y if (flip & 2) != 0 else y)
			if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(sample_at) or image.get_pixelv(sample_at).a < 0.999:
				return false
	return true
