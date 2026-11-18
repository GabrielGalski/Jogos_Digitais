extends SceneTree
## Mechanical asset preparation for the ImageGen source, then Godot resources.
## Run -- --art, import the project, then run -- --resources.

const SOURCE: String = "res://assets/tiles/floor/source/purple_floor_generated_v1.png"
const ATLAS: String = "res://assets/tiles/floor/purple_floor_v1.png"
const TILESET: String = "res://resources/purple_floor_tileset_16.tres"
const PALETTE: Array[Color] = [Color("25131a"), Color("362030"), Color("3d253b"),
	Color("45283c"), Color("533048"), Color("6f4358")]
const FAMILIES: Array[String] = ["earth", "gravel", "cracked", "tufts", "paving", "path_edges", "path_junctions", "broken_stone"]


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--art"):
		_prepare_native_atlas()
	elif arguments.has("--resources"):
		_build_tileset()
	else:
		push_error("Use -- --art or -- --resources")
		quit(1)


func _prepare_native_atlas() -> void:
	var image: Image = Image.load_from_file(SOURCE)
	if image == null or image.is_empty():
		push_error("Purple floor ImageGen source is missing")
		quit(1)
		return
	# Native nearest sampling and exact palette mapping; no procedural art.
	image.resize(256, 256, Image.INTERPOLATE_NEAREST)
	image.convert(Image.FORMAT_RGBA8)
	var counts: Dictionary = {}
	for y: int in range(256):
		for x: int in range(256):
			var pixel: Color = image.get_pixel(x, y)
			var closest: Color = PALETTE[0]
			var smallest: float = INF
			for candidate: Color in PALETTE:
				var distance: float = pow(pixel.r - candidate.r, 2.0) + pow(pixel.g - candidate.g, 2.0) + pow(pixel.b - candidate.b, 2.0)
				if distance < smallest:
					smallest = distance
					closest = candidate
			image.set_pixel(x, y, closest)
			counts[closest.to_html(false)] = int(counts.get(closest.to_html(false), 0)) + 1
	if image.save_png(ATLAS) != OK:
		push_error("Could not save purple floor atlas")
		quit(1)
		return
	print("PURPLE FLOOR ART: 256x256, 16px tiles, opaque, exact palette ", counts)
	quit()


func _build_tileset() -> void:
	var texture: Texture2D = load(ATLAS) as Texture2D
	if texture == null or texture.get_size() != Vector2(256, 256):
		push_error("Import the native purple floor atlas first")
		quit(1)
		return
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(16, 16)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, "ground_family")
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(16, 16)
	tile_set.add_source(source, 0)
	for y: int in range(16):
		for x: int in range(16):
			var cell: Vector2i = Vector2i(x, y)
			source.create_tile(cell)
			source.get_tile_data(cell, 0).set_custom_data(&"ground_family", FAMILIES[floori(float(y) / 2.0)])
	if ResourceSaver.save(tile_set, TILESET) != OK:
		push_error("Could not save purple floor TileSet")
		quit(1)
		return
	print("PURPLE FLOOR TILESET: 256 tiles, native 16x16, 8 families, no physics")
	quit()
