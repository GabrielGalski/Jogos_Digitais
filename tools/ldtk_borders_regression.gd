extends SceneTree
## Exhaustive native-pixel physics test, flips, offsets, player-size sweeping and arena wiring.

const BORDERS: Script = preload("res://scripts/dungeon/ldtk_borders.gd")
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
const SOURCE: String = "assets/tiles/wall/bordas.png"
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	var capture: bool = "--capture" in OS.get_cmdline_user_args()
	if capture:
		root.content_scale_size = Vector2i(640, 180)
		root.size = Vector2i(1280, 360)
		RenderingServer.set_default_clear_color(Color("#1c1122"))
	var world: Node2D = Node2D.new()
	root.add_child(world)
	var borders: Node2D = BORDERS.new() as Node2D
	world.add_child(borders)
	var tiles: Array = []
	for flip: int in range(4):
		for row: int in range(16):
			for col: int in range(16):
				tiles.append({"px": [flip * 160 + col * 8, row * 8], "src": [col * 8, row * 8], "f": flip})
	var layer: Dictionary = {"__identifier": "Borders", "__tilesetDefUid": 1,
		"__pxTotalOffsetX": 13, "__pxTotalOffsetY": 19, "gridTiles": tiles}
	var textures: RefCounted = TEXTURES.new()
	borders.call("build", [layer], {1: {"relPath": SOURCE, "tileGridSize": 8}}, textures)
	_check(borders.get_child_count() == 1, "Border tiles must batch into one TileMapLayer")
	await physics_frame
	await physics_frame
	var image: Image = textures.call("get_source_image", SOURCE) as Image
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	var differences: int = 0
	for flip: int in range(4):
		for y: int in range(128):
			for x: int in range(128):
				var sx: int = floori(x / 8.0) * 8 + (7 - x % 8 if flip & 1 else x % 8)
				var sy: int = floori(y / 8.0) * 8 + (7 - y % 8 if flip & 2 else y % 8)
				query.position = Vector2(13.5 + flip * 160 + x, 19.5 + y)
				var expected: bool = image.get_pixel(sx, sy).a >= 0.5
				var actual: bool = not space.intersect_point(query, 1).is_empty()
				if actual != expected:
					differences += 1
	_check(differences == 0, "Alpha/physics mismatch across native pixels and flips: " + str(differences))
	if capture:
		await process_frame
		await RenderingServer.frame_post_draw
		var capture_path: String = "res://output/ldtk/borders_flips.png"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/ldtk"))
		_check(root.get_texture().get_image().save_png(capture_path) == OK, "Could not capture the rendered borders")
	var body: CharacterBody2D = CharacterBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	# Same physical footprint as the player, without loading its gameplay controllers.
	var player_scene: PackedScene = load("res://scenes/player.tscn") as PackedScene
	var player: Node = player_scene.instantiate()
	var player_collision: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	shape.shape = player_collision.shape.duplicate() as Shape2D
	shape.position = player_collision.position
	body.add_child(shape)
	world.add_child(body)
	player.free()
	# Vertical bar x=96..103, y=96..127, offset by (13,19).
	body.position = Vector2(90, 130)
	await physics_frame
	_check(body.test_move(body.global_transform, Vector2(40, 0)), "Walking motion must hit the border")
	_check(body.test_move(body.global_transform, Vector2(300, 0)), "Fast dash sweep must hit the border")
	# Interior opening of the first U: x=0..15, y=16..63.
	body.position = Vector2(19, 51)
	_check(not body.test_move(body.global_transform, Vector2(0, 6)), "Transparent opening must remain traversable")
	var hidden: Node2D = BORDERS.new() as Node2D
	world.add_child(hidden)
	var hidden_layer: Dictionary = layer.duplicate(true)
	hidden_layer["visible"] = false
	hidden.call("build", [hidden_layer], {1: {"relPath": SOURCE}}, textures)
	_check(hidden.get_child_count() == 0, "Hidden Borders must not generate visuals or collision")
	world.queue_free()
	await process_frame
	var arena_scene: PackedScene = load("res://scenes/dungeon/ldtk_arena.tscn") as PackedScene
	var arena: Node2D = arena_scene.instantiate() as Node2D
	root.add_child(arena)
	await process_frame
	_check(str(arena.get("level_name")) == "Room_1", "Arena must keep starting in Room_1")
	_check(arena.has_node("Borders"), "Arena must configure the border adapter")
	arena.queue_free()
	await process_frame
	print(JSON.stringify({"ok": _failures.is_empty(), "native_pixels_checked": 65536, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)
