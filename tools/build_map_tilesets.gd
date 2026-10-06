extends SceneTree
## Offline authoring. Run --art, import, then --resources.

const WALL_SOURCE: String = "res://assets/tiles/wall/wall_tileset.png"
const WALL_PALETTE: String = "res://assets/tiles/editor/wall_palette.png"
const DOOR_PALETTE: String = "res://assets/tiles/editor/door_palette.png"
const OBJECT_PALETTE: String = "res://assets/tiles/editor/object_palette.png"
const TILESET_PATH: String = "res://resources/map_tileset_16.tres"
const TILE: int = 16

var tile_set: TileSet

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("Use -- --art or -- --resources")
		quit(1)
		return
	if arguments[0] == "--art":
		_build_art()
	elif arguments[0] == "--resources":
		_build_resources()
	else:
		push_error("Unknown mode: " + arguments[0])
		quit(1)

func _build_art() -> void:
	var directory: String = ProjectSettings.globalize_path("res://assets/tiles/editor")
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var wall_image: Image = Image.create_empty(256, 368, false, Image.FORMAT_RGBA8)
	wall_image.fill(Color.TRANSPARENT)
	for variant: int in range(4):
		var source_y: int = 16 + variant * 64
		var dest_y: int = variant * 64
		for cut: Vector2i in [Vector2i(0, 64), Vector2i(64, 48),
				Vector2i(112, 32), Vector2i(144, 16)]:
			_copy(wall_image, WALL_SOURCE, Rect2i(192, source_y, cut.y, 48),
				Vector2i(cut.x, dest_y))
		# The single-pixel edge sits in the final column of a transparent 16px cell.
		_copy(wall_image, WALL_SOURCE, Rect2i(191, source_y, 1, 48),
			Vector2i(175, dest_y))
	_copy(wall_image, WALL_SOURCE, Rect2i(0, 128, 64, 48), Vector2i(0, 256)) # IE
	_copy(wall_image, WALL_SOURCE, Rect2i(112, 128, 64, 48), Vector2i(64, 256)) # ID
	_copy(wall_image, WALL_SOURCE, Rect2i(48, 16, 16, 48), Vector2i(128, 256)) # QE
	_copy(wall_image, WALL_SOURCE, Rect2i(127, 16, 17, 48), Vector2i(144, 256)) # QD
	_copy(wall_image, WALL_SOURCE, Rect2i(0, 64, 17, 48), Vector2i(176, 256)) # TSE
	_copy(wall_image, WALL_SOURCE, Rect2i(160, 64, 16, 48), Vector2i(208, 256)) # TSD
	_copy(wall_image, WALL_SOURCE, Rect2i(0, 208, 17, 48), Vector2i(0, 320)) # TIE
	_copy(wall_image, WALL_SOURCE, Rect2i(160, 208, 16, 48), Vector2i(32, 320)) # TID
	_copy(wall_image, WALL_SOURCE, Rect2i(0, 176, 16, 16), Vector2i(48, 320)) # LE
	_copy(wall_image, WALL_SOURCE, Rect2i(160, 176, 16, 16), Vector2i(64, 320)) # LD
	assert(wall_image.save_png(WALL_PALETTE) == OK)

	var door_image: Image = Image.create_empty(128, 32, false, Image.FORMAT_RGBA8)
	door_image.fill(Color.TRANSPARENT)
	var doors: PackedStringArray = [
		"door_front_closed_superior.png", "door_front_opened_superior.png",
		"door_front_closed_inferior.png", "door_front_opened_inferior.png"]
	for index: int in range(doors.size()):
		_copy(door_image, "res://assets/tiles/door/" + doors[index],
			Rect2i(0, 0, 32, 32), Vector2i(index * 32, 0))
	assert(door_image.save_png(DOOR_PALETTE) == OK)

	var object_image: Image = Image.create_empty(192, 128, false, Image.FORMAT_RGBA8)
	object_image.fill(Color.TRANSPARENT)
	_copy(object_image, "res://assets/tiles/wall/decor/column_square.png",
		Rect2i(0, 0, 32, 64), Vector2i(0, 0))
	_copy(object_image, "res://assets/tiles/wall/decor/column_round.png",
		Rect2i(0, 0, 32, 64), Vector2i(32, 0))
	_copy(object_image, "res://assets/tiles/wall/decor/stair.png",
		Rect2i(0, 0, 124, 124), Vector2i(64, 0))
	assert(object_image.save_png(OBJECT_PALETTE) == OK)
	print("MAP ART READY: wall 256x368, doors 128x32, objects 192x128")
	quit()

func _copy(target: Image, path: String, source_rect: Rect2i, at: Vector2i) -> void:
	var original: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	assert(original != null and not original.is_empty(), "Missing image: " + path)
	assert(Rect2i(Vector2i.ZERO, original.get_size()).encloses(source_rect),
		"Crop outside source: " + path)
	target.blit_rect(original, source_rect, at)

func _build_resources() -> void:
	assert(DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://scenes/maps")) == OK)
	tile_set = TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, "piece")
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)

	var floor_source: TileSetAtlasSource = _source(0, "01 Piso 16x16",
		"res://assets/tiles/floor/floor_tileset.png", Vector2i(16, 16))
	for y: int in range(3):
		for x: int in range(4):
			_tile(floor_source, Vector2i(x, y), Vector2i.ONE, Vector2i.ZERO,
				"floor_%d_%d" % [x, y])
	var underside: TileSetAtlasSource = _source(1, "02 Borda inferior 16x32",
		"res://assets/tiles/inferior/inferior.png", Vector2i(16, 32))
	for x: int in range(8):
		_tile(underside, Vector2i(x, 0), Vector2i.ONE, Vector2i(0, -8),
			"underside_%d" % x)

	var north: TileSetAtlasSource = _source(2, "03 Parede norte: base na linha pintada",
		WALL_PALETTE, Vector2i(16, 16))
	var south: TileSetAtlasSource = _source(3, "04 Parede sul: inicio na linha pintada",
		WALL_PALETTE, Vector2i(16, 16))
	for source: TileSetAtlasSource in [north, south]:
		var face_y: int = 32 if source == north else -16
		for variant: int in range(4):
			var row: int = variant * 4
			for section: Vector3i in [Vector3i(0, 4, 64), Vector3i(4, 3, 48),
					Vector3i(7, 2, 32), Vector3i(9, 1, 16)]:
				_tile(source, Vector2i(section.x, row), Vector2i(section.y, 3),
					Vector2i(8 - int(section.z / 2.0), face_y),
					"W%02d_%d" % [variant + 1, section.z])
			_tile(source, Vector2i(10, row), Vector2i(1, 3),
				Vector2i(0, face_y), "W%02d_edge_1px" % (variant + 1))
		for detail: Dictionary in [
			{"id":"IE", "x":0, "row":16, "cells":4, "offset":-24},
			{"id":"ID", "x":4, "row":16, "cells":4, "offset":-24},
			{"id":"QE", "x":8, "row":16, "cells":1, "offset":0},
			{"id":"QD", "x":9, "row":16, "cells":2, "offset":-7},
			{"id":"TSE", "x":11, "row":16, "cells":2, "offset":-8},
			{"id":"TSD", "x":13, "row":16, "cells":1, "offset":0},
			{"id":"TIE", "x":0, "row":20, "cells":2, "offset":-8},
			{"id":"TID", "x":2, "row":20, "cells":1, "offset":0}]:
			_tile(source, Vector2i(int(detail["x"]), int(detail["row"])),
				Vector2i(int(detail["cells"]), 3),
				Vector2i(int(detail["offset"]), face_y), String(detail["id"]))

	var sides: TileSetAtlasSource = _source(4, "05 Laterais LE e LD",
		WALL_PALETTE, Vector2i(16, 16))
	_tile(sides, Vector2i(3, 20), Vector2i.ONE, Vector2i(8, 0), "LE")
	_tile(sides, Vector2i(4, 20), Vector2i.ONE, Vector2i(-8, 0), "LD")

	var door_source: TileSetAtlasSource = _source(5, "06 Portas frontais",
		DOOR_PALETTE, Vector2i(16, 16))
	for index: int in range(4):
		var name: String = ["superior_closed", "superior_opened",
			"inferior_closed", "inferior_opened"][index]
		_tile(door_source, Vector2i(index * 2, 0), Vector2i(2, 2),
			Vector2i(-8, 24 if index < 2 else -8), "door_" + name)

	var objects: TileSetAtlasSource = _source(6, "07 Colunas e escada",
		OBJECT_PALETTE, Vector2i(16, 16))
	_tile(objects, Vector2i(0, 0), Vector2i(2, 4), Vector2i(0, 30), "column_square")
	_tile(objects, Vector2i(2, 0), Vector2i(2, 4), Vector2i(0, 30), "column_round")
	_tile(objects, Vector2i(4, 0), Vector2i(8, 8), Vector2i(0, 57), "stair_124")

	# The throne's authored scene remains authoritative. These raw visual
	# components are also exposed for map sketching on separate object layers.
	var throne_images: PackedStringArray = [
		"minotaur_chair.png", "minotaur_chair_back.png", "minotaur_chair_seat.png"]
	for index: int in range(throne_images.size()):
		var scene_piece: TileSetAtlasSource = _source(7 + index,
			"0%d Trono: %s" % [8 + index, throne_images[index]],
			"res://assets/tiles/decor/" + throne_images[index], Vector2i(128, 128))
		_tile(scene_piece, Vector2i.ZERO, Vector2i.ONE, Vector2i.ZERO,
			throne_images[index].get_basename())

	tile_set.resource_path = TILESET_PATH
	assert(ResourceSaver.save(tile_set, TILESET_PATH) == OK)
	_build_template()
	_build_preview()
	print("MAP TILESET READY: ", tile_set.get_source_count(),
		" named sources, 16px grid; template and preview saved")
	quit()

func _source(source_id: int, title: String, path: String,
		region: Vector2i) -> TileSetAtlasSource:
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.resource_name = title
	source.texture = load(path) as Texture2D
	assert(source.texture != null, "Import PNG first: " + path)
	source.texture_region_size = region
	assert(tile_set.add_source(source, source_id) == source_id)
	return source

func _tile(source: TileSetAtlasSource, coords: Vector2i, size: Vector2i,
		origin: Vector2i, piece: String) -> void:
	source.create_tile(coords, size)
	var data: TileData = source.get_tile_data(coords, 0)
	data.texture_origin = origin
	data.set_custom_data("piece", piece)

func _layer(parent: Node2D, name: String, z: int) -> TileMapLayer:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.name = name
	layer.z_index = z
	layer.tile_set = tile_set
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(layer)
	layer.owner = parent
	return layer

func _build_template() -> void:
	var map_root: Node2D = Node2D.new()
	map_root.name = "MapTemplate16"
	map_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for entry: Dictionary in [
		{"name":"PlatformUnderside", "z":-12},
		{"name":"Floor", "z":-10},
		{"name":"WallsBack", "z":-8},
		{"name":"WallsSides", "z":-7},
		{"name":"ObjectsBack", "z":-6},
		{"name":"WallsFront", "z":4},
		{"name":"Doors", "z":5},
		{"name":"ObjectsFront", "z":6}]:
		_layer(map_root, String(entry["name"]), int(entry["z"]))
	var scene: PackedScene = PackedScene.new()
	assert(scene.pack(map_root) == OK)
	assert(ResourceSaver.save(scene, "res://scenes/maps/map_template_16.tscn") == OK)
	map_root.free()

func _build_preview() -> void:
	var map_root: Node2D = Node2D.new()
	map_root.name = "TilePalettePreview"
	map_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var floor_layer: TileMapLayer = _layer(map_root, "Floor", -10)
	var back: TileMapLayer = _layer(map_root, "WallsBack", -8)
	var sides: TileMapLayer = _layer(map_root, "WallsSides", -7)
	var front: TileMapLayer = _layer(map_root, "WallsFront", 4)
	var doors: TileMapLayer = _layer(map_root, "Doors", 5)
	var objects: TileMapLayer = _layer(map_root, "Objects", 6)
	for y: int in range(12):
		for x: int in range(20):
			floor_layer.set_cell(Vector2i(x, y), 0, Vector2i(1, 1))
	# Two 16px cuts leave an actual 32px opening for each door.
	for x: int in [0, 4, 12, 16]:
		back.set_cell(Vector2i(x, 0), 2, Vector2i(0, posmod(int(x / 4.0), 4) * 4))
		front.set_cell(Vector2i(x, 12), 3, Vector2i(0, posmod(int(x / 4.0) + 2, 4) * 4))
	back.set_cell(Vector2i(8, 0), 2, Vector2i(9, 8))
	back.set_cell(Vector2i(11, 0), 2, Vector2i(9, 12))
	front.set_cell(Vector2i(8, 12), 3, Vector2i(9, 0))
	front.set_cell(Vector2i(11, 12), 3, Vector2i(9, 4))
	for y: int in range(12):
		sides.set_cell(Vector2i(0, y), 4, Vector2i(3, 20))
		sides.set_cell(Vector2i(19, y), 4, Vector2i(4, 20))
	doors.set_cell(Vector2i(9, 0), 5, Vector2i(0, 0))
	doors.set_cell(Vector2i(9, 12), 5, Vector2i(4, 0))
	objects.set_cell(Vector2i(7, 8), 6, Vector2i(0, 0))
	objects.set_cell(Vector2i(13, 8), 6, Vector2i(2, 0))
	var camera: Camera2D = Camera2D.new()
	camera.name = "PreviewCamera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(160, 96)
	camera.zoom = Vector2.ONE * 0.8
	map_root.add_child(camera)
	camera.owner = map_root
	var scene: PackedScene = PackedScene.new()
	assert(scene.pack(map_root) == OK)
	assert(ResourceSaver.save(scene, "res://scenes/maps/tile_palette_preview.tscn") == OK)
	map_root.free()
