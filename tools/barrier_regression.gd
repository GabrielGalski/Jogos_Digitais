extends SceneTree
## Native barrier alpha, swept player contact, flips and empty LDtk registration.

const BORDERS: Script = preload("res://scripts/dungeon/ldtk_borders.gd")
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
const SOURCE: String = "assets/tiles/floor/barrier.png"
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)


func _run() -> void:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	var adapter: Node2D = BORDERS.new() as Node2D
	adapter.set("layer_name", "Barriers")
	world.add_child(adapter)
	var stamps: Array = []
	for flip: int in range(4):
		for y: int in range(2):
			for x: int in range(7):
				stamps.append({"px": [flip * 160 + x * 16, y * 16], "src": [x * 16, y * 16], "f": flip})
	var instance: Dictionary = {"__identifier": "Barriers", "__tilesetDefUid": 1, "__pxTotalOffsetX": 13, "__pxTotalOffsetY": 19, "gridTiles": stamps}
	var textures: RefCounted = TEXTURES.new()
	adapter.call("build", [instance], {1: {"relPath": SOURCE, "tileGridSize": 16}}, textures)
	check(adapter.get_child_count() == 1, "Barrier pieces share one batched TileMapLayer")
	await physics_frame
	await physics_frame
	var image: Image = textures.call("get_source_image", SOURCE) as Image
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	var differences: int = 0
	for flip: int in range(4):
		for y: int in range(32):
			for x: int in range(112):
				var sx: int = floori(x / 16.0) * 16 + (15 - x % 16 if flip & 1 else x % 16)
				var sy: int = floori(y / 16.0) * 16 + (15 - y % 16 if flip & 2 else y % 16)
				query.position = Vector2(13.5 + flip * 160 + x, 19.5 + y)
				if (not space.intersect_point(query, 1).is_empty()) != (image.get_pixel(sx, sy).a >= 0.5): differences += 1
	check(differences == 0, "All 14,336 native pixels and flips match their physical silhouette")
	var player_source: Node2D = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Node2D
	var source_shape: CollisionShape2D = player_source.get_node("CollisionShape2D") as CollisionShape2D
	var body: CharacterBody2D = CharacterBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.shape = source_shape.shape.duplicate() as Shape2D
	shape.position = source_shape.position
	body.add_child(shape)
	world.add_child(body)
	player_source.free()
	await physics_frame
	check(body.test_move(Transform2D(0.0, Vector2(69, -5)), Vector2(0, 80)), "A player-sized body cannot walk through the barrier from above")
	check(body.test_move(Transform2D(0.0, Vector2(69, 83)), Vector2(0, -80)), "The barrier blocks the reverse crossing")
	check(body.test_move(Transform2D(0.0, Vector2(69, -5)), Vector2(0, 300)), "A fast dash sweep also hits the barrier")
	var hidden: Node2D = BORDERS.new() as Node2D
	hidden.set("layer_name", "Barriers")
	world.add_child(hidden)
	var hidden_data: Dictionary = instance.duplicate(true)
	hidden_data["visible"] = false
	hidden.call("build", [hidden_data], {1: {"relPath": SOURCE, "tileGridSize": 16}}, textures)
	check(hidden.get_child_count() == 0, "A hidden barrier layer adds no graphics or physics")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var levels: Array = preload("res://scripts/dungeon/ldtk_level_composition.gd").levels(data)
	var registered: bool = false
	for definition: Dictionary in (data.defs as Dictionary).get("tilesets", []):
		if str(definition.get("relPath", "")) == SOURCE:
			registered = true
			check(int(definition.tileGridSize) == 16 and int(definition.pxWid) == 112 and int(definition.pxHei) == 32, "The native 7 by 2 atlas is registered without rescaling")
	check(registered, "Barrier source is present in the LDtk catalog")
	for level_data: Dictionary in levels:
		for layer: Dictionary in level_data.get("layerInstances", []):
			if str(layer.get("__identifier", "")) == "Barriers":
				check(int(layer.get("__gridSize", 0)) == 16, "Authored barrier layers retain the registered native grid")
	print("BARRIER_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)
