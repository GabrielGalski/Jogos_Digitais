extends SceneTree

const GEOMETRY: Script = preload("res://scripts/dungeon/ldtk_map_geometry.gd")
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for label: String in ["authored", "flips"]:
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tmp/walls_8_%s_before.ldtk" % label)) as Dictionary
		var converted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tmp/walls_8_%s_after.ldtk" % label)) as Dictionary
		var level: Dictionary = (original.levels as Array)[0]
		root.size = Vector2i(int(level.pxWid), int(level.pxHei))
		root.content_scale_size = root.size
		var old_world: Node2D = _build(original)
		await physics_frame
		await process_frame
		var before: Array[String] = _snapshot(old_world)
		var old_pixels: PackedByteArray = PackedByteArray()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var old_image: Image = root.get_texture().get_image()
			old_pixels = old_image.get_data()
			DirAccess.make_dir_recursive_absolute("res://renders")
			assert(old_image.save_png("res://renders/walls_8_%s_before.png" % label) == OK)
		old_world.free()
		var new_world: Node2D = _build(converted)
		await physics_frame
		await process_frame
		assert(before == _snapshot(new_world), "Mudou profundidade/colisao do mapa " + label)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var new_image: Image = root.get_texture().get_image()
			assert(new_image.get_data() == old_pixels, "Mudou imagem renderizada do mapa " + label)
			assert(new_image.save_png("res://renders/walls_8_%s_after.png" % label) == OK)
		new_world.free()
		print("WALLS 8 PASS %s: exact same physical footprints, depth groups and rendered pixels" % label)
	quit(0)


func _build(data: Dictionary) -> Node2D:
	var world: Node2D = Node2D.new()
	world.y_sort_enabled = true
	root.add_child(world)
	var definitions: Dictionary = {}
	for definition: Dictionary in (data.defs as Dictionary).tilesets:
		definitions[int(definition.uid)] = definition
	var floor_cells: Dictionary = {}
	var layers: Array = ((data.levels as Array)[0] as Dictionary).layerInstances
	for layer: Dictionary in layers:
		if str(layer.__identifier) == "Floor":
			for tile: Dictionary in layer.gridTiles:
				floor_cells[Vector2i(floori(float(tile.px[0]) / 16.0), floori(float(tile.px[1]) / 16.0))] = true
	var geometry: RefCounted = GEOMETRY.new()
	var textures: RefCounted = TEXTURES.new()
	geometry.call("build", world, layers, definitions, floor_cells, textures)
	return world


func _snapshot(world: Node2D) -> Array[String]:
	var records: Array[String] = []
	for node: Node2D in world.get_children():
		if node.has_meta("footprint"):
			records.append(str([node.get_meta("kind"), node.get_meta("authored_origin"), node.get_meta("footprint"), node.position, node.z_index]))
	records.sort()
	return records
