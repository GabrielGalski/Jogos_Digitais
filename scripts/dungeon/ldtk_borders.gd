extends Node2D
## Border/barrier tiles: shared native atlas, alpha-shaped collision on world layer 1.

const LAYER_NAME: String = "Borders"
@export var layer_name: String = LAYER_NAME
@export_range(0.5, 3.0, 0.05) var brightness: float = 1.0


func build(layers: Array, definitions: Dictionary, textures: RefCounted) -> void:
	z_index = -16
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	modulate = Color(brightness, brightness, brightness, 1.0)
	for layer_variant: Variant in layers:
		var layer: Dictionary = layer_variant
		if str(layer.get("__identifier", "")) != layer_name or not bool(layer.get("visible", true)):
			continue
		var tiles: Array = []
		tiles.append_array(layer.get("autoLayerTiles", []))
		tiles.append_array(layer.get("gridTiles", []))
		if tiles.is_empty():
			continue
		var definition: Dictionary = definitions.get(int(layer.get("__tilesetDefUid", -1)), {})
		var source_path: String = str(definition.get("relPath", ""))
		var texture: Texture2D = textures.call("get_texture", source_path) as Texture2D
		var image: Image = textures.call("get_source_image", source_path) as Image
		if texture == null or image == null:
			push_error("Borders: PNG ausente: " + source_path)
			continue
		var grid: int = int(definition.get("tileGridSize", 8))
		var tile_set: TileSet = TileSet.new()
		tile_set.tile_size = Vector2i(grid, grid)
		tile_set.add_physics_layer()
		tile_set.set_physics_layer_collision_layer(0, 1)
		tile_set.set_physics_layer_collision_mask(0, 0)
		var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
		atlas.texture = texture
		atlas.texture_region_size = Vector2i(grid, grid)
		tile_set.add_source(atlas, 0)
		var stack_counts: Dictionary[Vector2i, int] = {}
		var render_layers: Array[TileMapLayer] = []
		for tile_variant: Variant in tiles:
			var tile: Dictionary = tile_variant
			var pixel: Array = tile.get("px", [])
			var source_pixel: Array = tile.get("src", [])
			if pixel.size() != 2 or source_pixel.size() != 2:
				continue
			var source: Vector2i = Vector2i(int(source_pixel[0]), int(source_pixel[1]))
			if source.x < 0 or source.y < 0 or source.x + grid > image.get_width() or source.y + grid > image.get_height():
				push_error("Borders: tile fora do atlas: " + str(source))
				continue
			var atlas_cell: Vector2i = Vector2i(Vector2(source) / float(grid))
			if not atlas.has_tile(atlas_cell):
				atlas.create_tile(atlas_cell)
				add_alpha_collision(atlas.get_tile_data(atlas_cell, 0), image, Rect2i(source, Vector2i(grid, grid)))
			var cell: Vector2i = Vector2i(floori(float(pixel[0]) / grid), floori(float(pixel[1]) / grid))
			var depth: int = stack_counts.get(cell, 0)
			stack_counts[cell] = depth + 1
			while render_layers.size() <= depth:
				var render_layer: TileMapLayer = TileMapLayer.new()
				render_layer.name = layer_name + "_" + str(render_layers.size())
				render_layer.tile_set = tile_set
				render_layer.position = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
				render_layer.modulate.a = float(layer.get("__opacity", 1))
				add_child(render_layer)
				render_layers.append(render_layer)
			var flags: int = 0
			var flip: int = int(tile.get("f", 0))
			if flip & 1:
				flags |= TileSetAtlasSource.TRANSFORM_FLIP_H
			if flip & 2:
				flags |= TileSetAtlasSource.TRANSFORM_FLIP_V
			render_layers[depth].set_cell(cell, 0, atlas_cell, flags)


static func add_alpha_collision(data: TileData, image: Image, region: Rect2i) -> void:
	# Merge equal opaque runs vertically; never fill the transparent openings of a stamp.
	var rectangles: Array[Rect2i] = []
	var previous: Dictionary[Vector2i, int] = {}
	for y: int in range(region.size.y):
		var current: Dictionary[Vector2i, int] = {}
		var x: int = 0
		while x < region.size.x:
			if image.get_pixelv(region.position + Vector2i(x, y)).a < 0.5:
				x += 1
				continue
			var start: int = x
			while x < region.size.x and image.get_pixelv(region.position + Vector2i(x, y)).a >= 0.5:
				x += 1
			var run: Vector2i = Vector2i(start, x - start)
			var index: int = previous.get(run, -1)
			if index >= 0:
				var rect: Rect2i = rectangles[index]
				rect.size.y += 1
				rectangles[index] = rect
			else:
				index = rectangles.size()
				rectangles.append(Rect2i(start, y, x - start, 1))
			current[run] = index
		previous = current
	for rect: Rect2i in rectangles:
		var top_left: Vector2 = Vector2(rect.position) - Vector2(region.size) * 0.5
		var bottom_right: Vector2 = top_left + Vector2(rect.size)
		var polygon_index: int = data.get_collision_polygons_count(0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, polygon_index, PackedVector2Array([
			top_left, Vector2(bottom_right.x, top_left.y), bottom_right, Vector2(top_left.x, bottom_right.y)
		]))
