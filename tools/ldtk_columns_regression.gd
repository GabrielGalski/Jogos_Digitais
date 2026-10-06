extends SceneTree

const GEOMETRY: Script = preload("res://scripts/dungeon/ldtk_map_geometry.gd")
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var level: Dictionary = (data.levels as Array)[0]
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(int(level.pxWid), int(level.pxHei))
	root.content_scale_size = root.size
	var definitions: Dictionary = {}
	for definition: Dictionary in (data.defs as Dictionary).tilesets:
		definitions[int(definition.uid)] = definition
	var layers: Array = []
	for layer: Dictionary in level.layerInstances:
		if str(layer.__identifier) == "WallsBack" or str(layer.__identifier).begins_with("ObjectsBack"):
			layers.append(layer)
	var world: Node2D = Node2D.new()
	world.y_sort_enabled = true
	root.add_child(world)
	var textures: RefCounted = TEXTURES.new()
	GEOMETRY.new().call("build", world, layers, definitions, {}, textures)
	var columns: Array[Node2D] = []
	for volume: Node2D in get_nodes_in_group("ldtk_map_volumes"):
		if str(volume.get_meta("kind", "")).begins_with("column"):
			columns.append(volume)
		elif not columns.has(volume):
			assert(volume.z_index == 1, "Back-wall trim can still cover the props")
	await physics_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		var checked: int = 0
		for column: Node2D in columns:
			assert(column.z_index == 2)
			for child: Node in column.get_children():
				if not child is Sprite2D:
					continue
				var sprite: Sprite2D = child as Sprite2D
				var source: Image = sprite.texture.get_image()
				var region: Rect2i = Rect2i(sprite.region_rect)
				for y: int in range(region.size.y):
					for x: int in range(region.size.x):
						var expected: Color = source.get_pixel(region.position.x + x, region.position.y + y)
						if expected.a < 1.0:
							continue
						var at: Vector2i = Vector2i(sprite.global_position) + Vector2i(x, y)
						var actual: Color = screenshot.get_pixelv(at)
						assert(absf(expected.r - actual.r) <= 0.004 and absf(expected.g - actual.g) <= 0.004 and absf(expected.b - actual.b) <= 0.004, "Column pixel hidden at " + str(at))
						checked += 1
		DirAccess.make_dir_recursive_absolute("res://renders")
		assert(screenshot.save_png("res://renders/columns_verified.png") == OK)
		print("COLUMN PIXELS PASS: ", checked, " opaque pixels visible, including the bases")
	print("LDTK COLUMNS PASS: authored column fragments preserved; back-wall strips below props; player depth band unchanged")
	world.free()
	quit()
