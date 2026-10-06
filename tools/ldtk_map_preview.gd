extends SceneTree

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk"))
	var level: Dictionary = data.levels[0]
	var images: Dictionary = {}
	for entry: Dictionary in data.defs.tilesets:
		images[int(entry.uid)] = (load("res://" + str(entry.relPath)) as Texture2D).get_image()
	var result: Image = Image.create(int(level.pxWid), int(level.pxHei), false, Image.FORMAT_RGBA8)
	result.fill(Color("25131a"))
	var layers: Array = level.layerInstances.duplicate()
	layers.reverse()
	for layer: Dictionary in layers:
		for tile: Dictionary in layer.gridTiles:
			var source: Image = images[int(layer.__tilesetDefUid)]
			result.blend_rect(source, Rect2i(int(tile.src[0]), int(tile.src[1]), 16, 16), Vector2i(int(tile.px[0]), int(tile.px[1])))
	DirAccess.make_dir_recursive_absolute("res://tests")
	result.save_png("res://tests/ldtk_map_overview.png")
	quit()
