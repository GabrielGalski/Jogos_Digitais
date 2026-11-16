extends RefCounted
## Align legacy south-cliff solid bands with the actual opaque foot of the artwork.
## Like bridge preparation, this adapts runtime layers without rewriting the LDtk file.


static func prepare_layers(layers: Array, definitions: Dictionary, textures: RefCounted) -> Array:
	var bases: Dictionary[Vector2i, bool] = {}
	for layer: Dictionary in layers:
		if str(layer.get("__identifier", "")) != "TerrainFaces" or not bool(layer.get("visible", true)): continue
		var definition: Dictionary = definitions.get(int(layer.get("__tilesetDefUid", -1)), {}) as Dictionary
		var path: String = str(definition.get("relPath", ""))
		if not path.ends_with("/cliff_tileset.png"): continue
		var image: Image = textures.call("get_source_image", path) as Image
		if image == null: continue
		var grid: int = int(definition.get("tileGridSize", 16))
		var offset: Vector2i = Vector2i(int(layer.get("__pxTotalOffsetX", 0)), int(layer.get("__pxTotalOffsetY", 0)))
		for tile: Dictionary in layer.get("gridTiles", []):
			var source: Vector2i = Vector2i(int(tile.src[0]), int(tile.src[1]))
			if source.y != image.get_height() - grid or (int(tile.get("f", 0)) & 2) != 0: continue
			var used: Rect2i = image.get_region(Rect2i(source, Vector2i.ONE * grid)).get_used_rect()
			if not used.has_area(): continue
			var point: Vector2i = Vector2i(int(tile.px[0]), int(tile.px[1])) + offset
			var baseline: int = point.y + used.end.y
			if baseline % 16 != 0: continue
			bases[Vector2i(floori(float(point.x) / 16.0), floori(float(baseline) / 16.0))] = true
	if bases.is_empty(): return layers
	var result: Array = layers.duplicate()
	for index: int in range(result.size()):
		var layer: Dictionary = result[index] as Dictionary
		if str(layer.get("__identifier", "")) != "Gameplay" or int(layer.get("__gridSize", 16)) != 16: continue
		var width: int = int(layer.get("__cWid", 1))
		var height: int = int(layer.get("__cHei", 1))
		var values: Array = (layer.get("intGridCsv", []) as Array).duplicate()
		var changed: int = 0
		for base: Vector2i in bases:
			if base.x < 0 or base.x >= width or base.y < 1 or base.y >= height: continue
			var destination: int = (base.y - 1) * width + base.x
			if int(values[destination]) != 0: continue
			var count: int = 0
			while base.y + count < height and count < 8 and int(values[(base.y + count) * width + base.x]) == 6: count += 1
			# Match only the obsolete multi-row solid skirt, never unrelated single walls.
			if count < 2: continue
			for row: int in range(count): values[(base.y + row) * width + base.x] = 0
			values[destination] = 6
			changed += 1
		if changed > 0:
			var prepared: Dictionary = layer.duplicate()
			prepared["intGridCsv"] = values
			prepared["cliff_collision_fixed_columns"] = changed
			result[index] = prepared
	return result
