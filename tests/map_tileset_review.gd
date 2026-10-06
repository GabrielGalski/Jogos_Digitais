extends SceneTree
## Checks the authored palette and produces a visual reference for map editing.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var tiles: TileSet = load("res://resources/map_tileset_16.tres") as TileSet
	assert(tiles != null and tiles.tile_size == Vector2i(16, 16))
	assert(tiles.get_source_count() == 10)
	var north: TileSetAtlasSource = tiles.get_source(2) as TileSetAtlasSource
	var south: TileSetAtlasSource = tiles.get_source(3) as TileSetAtlasSource
	assert(north.get_tiles_count() == 28 and south.get_tiles_count() == 28)
	assert((tiles.get_source(0) as TileSetAtlasSource).get_tiles_count() == 12)
	assert((tiles.get_source(1) as TileSetAtlasSource).get_tiles_count() == 8)
	assert((tiles.get_source(5) as TileSetAtlasSource).get_tiles_count() == 4)
	assert(north.get_tile_data(Vector2i.ZERO, 0).texture_origin == Vector2i(-24, 32))
	assert(south.get_tile_data(Vector2i.ZERO, 0).texture_origin == Vector2i(-24, -16))
	assert(north.get_tile_data(Vector2i(0, 0), 0).get_custom_data("piece") == "W01_64")
	for variant: int in range(4):
		for cut: Vector2i in [Vector2i(0, 64), Vector2i(64, 48),
				Vector2i(112, 32), Vector2i(144, 16)]:
			_compare_region("res://assets/tiles/wall/wall_tileset.png",
				"res://assets/tiles/editor/wall_palette.png",
				Rect2i(192, 16 + variant * 64, cut.y, 48),
				Vector2i(cut.x, variant * 64))
		_compare_region("res://assets/tiles/wall/wall_tileset.png",
			"res://assets/tiles/editor/wall_palette.png",
			Rect2i(191, 16 + variant * 64, 1, 48),
			Vector2i(175, variant * 64))
	for detail: Dictionary in [
		{"source":Rect2i(0, 128, 64, 48), "at":Vector2i(0, 256)},
		{"source":Rect2i(112, 128, 64, 48), "at":Vector2i(64, 256)},
		{"source":Rect2i(48, 16, 16, 48), "at":Vector2i(128, 256)},
		{"source":Rect2i(127, 16, 17, 48), "at":Vector2i(144, 256)},
		{"source":Rect2i(0, 64, 17, 48), "at":Vector2i(176, 256)},
		{"source":Rect2i(160, 64, 16, 48), "at":Vector2i(208, 256)},
		{"source":Rect2i(0, 208, 17, 48), "at":Vector2i(0, 320)},
		{"source":Rect2i(160, 208, 16, 48), "at":Vector2i(32, 320)},
		{"source":Rect2i(0, 176, 16, 16), "at":Vector2i(48, 320)},
		{"source":Rect2i(160, 176, 16, 16), "at":Vector2i(64, 320)}]:
		_compare_region("res://assets/tiles/wall/wall_tileset.png",
			"res://assets/tiles/editor/wall_palette.png",
			detail["source"] as Rect2i, detail["at"] as Vector2i)
	for index: int in range(4):
		var door_name: String = [
			"door_front_closed_superior.png", "door_front_opened_superior.png",
			"door_front_closed_inferior.png", "door_front_opened_inferior.png"][index]
		_compare_region("res://assets/tiles/door/" + door_name,
			"res://assets/tiles/editor/door_palette.png",
			Rect2i(0, 0, 32, 32), Vector2i(index * 32, 0))
	for decoration: Dictionary in [
		{"name":"column_square.png", "size":Vector2i(32, 64), "at":Vector2i.ZERO},
		{"name":"column_round.png", "size":Vector2i(32, 64), "at":Vector2i(32, 0)},
		{"name":"stair.png", "size":Vector2i(124, 124), "at":Vector2i(64, 0)}]:
		_compare_region("res://assets/tiles/wall/decor/" + String(decoration["name"]),
			"res://assets/tiles/editor/object_palette.png",
			Rect2i(Vector2i.ZERO, decoration["size"] as Vector2i),
			decoration["at"] as Vector2i)
	var template: Node2D = (load("res://scenes/maps/map_template_16.tscn") as PackedScene).instantiate() as Node2D
	assert(template.get_child_count() == 8)
	for node: Node in template.get_children():
		var layer: TileMapLayer = node as TileMapLayer
		assert(layer != null and layer.tile_set == tiles)
		assert(layer.get_used_cells().is_empty())
	template.free()
	var preview: Node2D = (load("res://scenes/maps/tile_palette_preview.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(preview)
	var camera: Camera2D = preview.get_node("PreviewCamera") as Camera2D
	camera.make_current()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	assert(screenshot.save_png("res://renders/map_tile_palette_preview.png") == OK)
	print("MAP TILESETS PASS: 10 sources, 88 tiles, exact cuts, shared resource, editable layers, rendered preview")
	quit()

func _compare_region(original_path: String, palette_path: String,
		source_rect: Rect2i, target: Vector2i) -> void:
	var original: Image = Image.load_from_file(ProjectSettings.globalize_path(original_path))
	var palette: Image = Image.load_from_file(ProjectSettings.globalize_path(palette_path))
	for y: int in range(source_rect.size.y):
		for x: int in range(source_rect.size.x):
			assert(original.get_pixel(source_rect.position.x + x, source_rect.position.y + y) ==
				palette.get_pixel(target.x + x, target.y + y),
				"Pixel differs: " + original_path + " " + str(source_rect))
