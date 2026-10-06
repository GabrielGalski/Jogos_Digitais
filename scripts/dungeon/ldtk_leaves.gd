extends Node2D
## Non-physical foreground canopy, without projected light or halo.

const FOREGROUND_Z: int = 1000


static func is_leaves_source(definition: Dictionary) -> bool:
	return str(definition.get("relPath", "")).replace("\\", "/").ends_with("/leaves.png")


func build(layers: Array, definitions: Dictionary, texture_source: RefCounted) -> void:
	z_as_relative = false
	z_index = FOREGROUND_Z
	y_sort_enabled = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var patches: Dictionary = {}
	for layer: Dictionary in layers:
		var source_variant: Variant = layer.get("__tilesetDefUid")
		var source_id: int = int(source_variant) if source_variant != null else -1
		if not definitions.has(source_id) or not is_leaves_source(definitions[source_id]):
			continue
		if not bool(layer.get("visible", true)):
			continue
		var path: String = str((definitions[source_id] as Dictionary).get("relPath", ""))
		var texture: Texture2D = texture_source.call("get_texture", path) as Texture2D
		var image: Image = texture_source.call("get_source_image", path) as Image
		if texture == null or image == null:
			push_error("PNG de folhas ausente: " + path)
			continue
		var grid: int = int(layer.get("__gridSize", 16))
		var tiles: Array = layer.get("autoLayerTiles", []).duplicate()
		tiles.append_array(layer.get("gridTiles", []))
		for tile: Dictionary in tiles:
			var source: Vector2i = Vector2i(int(tile.src[0]), int(tile.src[1]))
			var used: Rect2i = image.get_region(Rect2i(source, Vector2i(grid, grid))).get_used_rect()
			if not used.has_area():
				continue
			var pixel: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1]))
			pixel += Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
			var flip: int = int(tile.get("f", 0))
			var stamp_source: Vector2i = source
			if (flip & 1) != 0:
				stamp_source.x = image.get_width() - grid - source.x
				used.position.x = grid - used.end.x
			if (flip & 2) != 0:
				stamp_source.y = image.get_height() - grid - source.y
				used.position.y = grid - used.end.y
			var origin: Vector2 = pixel - Vector2(stamp_source)
			var key: String = "%s:%s:%s" % [layer.get("iid", layer.get("__identifier", "")), origin, flip]
			var bounds: Rect2 = Rect2(pixel + Vector2(used.position), Vector2(used.size))
			if not patches.has(key):
				patches[key] = {"bounds": bounds, "sprites": []}
			var patch: Dictionary = patches[key]
			patch.bounds = (patch.bounds as Rect2).merge(bounds)
			var sprite: Sprite2D = Sprite2D.new()
			sprite.texture = texture
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(Vector2(source), Vector2.ONE * grid)
			sprite.position = pixel
			sprite.flip_h = (flip & 1) != 0
			sprite.flip_v = (flip & 2) != 0
			sprite.modulate.a = float(tile.get("a", 1)) * float(layer.get("__opacity", 1))
			(patch.sprites as Array).append(sprite)
	for patch: Dictionary in patches.values():
		_finish_patch(patch)


func _finish_patch(patch: Dictionary) -> void:
	var bounds: Rect2 = patch.bounds
	var canopy: Node2D = Node2D.new()
	canopy.name = "Leaves_%d" % get_child_count()
	canopy.position = bounds.position
	canopy.set_meta("painted_bounds", bounds)
	add_child(canopy)
	canopy.add_to_group("ldtk_leaves")
	for sprite: Sprite2D in patch.sprites:
		sprite.position -= bounds.position
		canopy.add_child(sprite)
