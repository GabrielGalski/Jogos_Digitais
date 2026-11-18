extends SceneTree
## Authored plants, real actor/bush collisions and reactive grass idle return.

const VEGETATION: Script = preload("res://scripts/dungeon/ldtk_vegetation.gd")
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
const RUNTIME_TREES: Script = preload("res://scripts/dungeon/ldtk_trees.gd")
const MINOTAUR: PackedScene = preload("res://scenes/enemies/minotaur.tscn")
const SPIRIT: Script = preload("res://scripts/enemies/spirit_ghost.gd")
var failures: Array[String] = []
var arena: Node2D = null
var player: Player = null
var fixture: Node2D = null
var rendered: bool = false
var view: SubViewport = null
var home: Vector2 = Vector2(-1200, -1200)


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func layer(name: String, source_id: int, origins: Array[Vector2], size: int, shown: bool = true, flip: int = 0) -> Dictionary:
	var tiles: Array[Dictionary] = []
	for origin: Vector2 in origins:
		for y: int in range(0, size, 16):
			for x: int in range(0, size, 16):
				var mirrored_x: int = size - 16 - x if (flip & 1) != 0 else x
				var mirrored_y: int = size - 16 - y if (flip & 2) != 0 else y
				tiles.append({"px": [origin.x + mirrored_x, origin.y + mirrored_y], "src": [x, y], "f": flip, "a": 1.0})
	return {"__identifier": name, "iid": name, "visible": shown, "__gridSize": 16,
		"__tilesetDefUid": source_id, "gridTiles": tiles, "autoLayerTiles": []}


func ticks() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func move_to(point: Vector2) -> void:
	player.global_position = home + point
	player.reset_physics_interpolation()
	await ticks()


func capture(name: String) -> void:
	if not rendered: return
	await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://output/vegetation/" + name + ".png")


func _check_authored_content() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(arena.get("map_path"))))
	check(parsed is Dictionary, "Authored LDtk data is available for vegetation counts")
	if not parsed is Dictionary: return
	var map_data: Dictionary = parsed as Dictionary
	var definitions: Dictionary = {}
	var map_definitions: Dictionary = map_data.get("defs", {}) as Dictionary
	for definition: Dictionary in map_definitions.get("tilesets", []):
		definitions[int(definition.get("uid", -1))] = definition
	var authored_layers: Array = arena.get("_level_layers") as Array
	# Use the tree mapper to count coherent stamps, including flipped and clipped
	# selections. Counting painted 16 px fragments would overcount whole crowns.
	var mapped_trees: Node2D = RUNTIME_TREES.new() as Node2D
	mapped_trees.call("build", authored_layers, definitions, TEXTURES.new())
	var expected_trees: int = mapped_trees.get_child_count()
	var expected_casters: int = (mapped_trees.call("shadow_descriptions") as Array).size()
	check(arena.get_node("Trees").get_child_count() == expected_trees, "Runtime trees match visible authored tree stamps")
	var shadows: Node2D = arena.get_node("TreeShadows") as Node2D
	check(shadows.get_child_count() == (1 if expected_casters > 0 else 0), "Authored trees share one shadow sprite; empty paint leaves no residual shadow")
	if expected_casters > 0:
		check(int(shadows.get_meta(&"caster_count", -1)) == expected_casters, "Merged shadow includes every visible authored tree caster")
	mapped_trees.free()
	var expected_bushes: Dictionary[String, bool] = {}
	var expected_grasses: int = 0
	for authored_layer: Dictionary in authored_layers:
		if not bool(authored_layer.get("visible", true)): continue
		var source_id: int = int(authored_layer.get("__tilesetDefUid", -1)) if authored_layer.get("__tilesetDefUid") != null else -1
		var definition: Dictionary = definitions.get(source_id, {}) as Dictionary
		var source_path: String = str(definition.get("relPath", "")).replace("\\", "/")
		var is_grass: bool = source_path.ends_with("/grass_animated1.png")
		if not is_grass and not source_path.ends_with("/bush.png"): continue
		var tiles: Array = (authored_layer.get("autoLayerTiles", []) as Array).duplicate()
		tiles.append_array(authored_layer.get("gridTiles", []))
		var grid: int = int(authored_layer.get("__gridSize", 16))
		var offset: Vector2 = Vector2(float(authored_layer.get("__pxTotalOffsetX", 0)), float(authored_layer.get("__pxTotalOffsetY", 0)))
		for tile: Dictionary in tiles:
			if float(tile.get("a", 1.0)) * float(authored_layer.get("__opacity", 1.0)) <= 0.0: continue
			if is_grass:
				expected_grasses += 1
				continue
			var flip: int = int(tile.get("f", 0))
			var source: Vector2 = Vector2(float(tile.src[0]), float(tile.src[1]))
			if (flip & 1) != 0: source.x = 32.0 - float(grid) - source.x
			if (flip & 2) != 0: source.y = 32.0 - float(grid) - source.y
			var origin: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1])) + offset - source
			var key: String = "%s:%s:%s" % [authored_layer.get("iid", authored_layer.get("__identifier", "")), origin, flip]
			expected_bushes[key] = true
	var actual: Node2D = arena.get_node("Vegetation") as Node2D
	check((actual.get("bushes") as Array).size() == expected_bushes.size(), "Runtime bushes match visible authored 32 px stamps")
	check((actual.get("grasses") as Array).size() == expected_grasses, "Runtime reactive grass matches every visible grass_animated1 tile")
	check(actual.get_child_count() == expected_bushes.size() + expected_grasses, "Vegetation contains only the plants painted in visible layers")
	check(actual.is_physics_processing() == (expected_grasses > 0), "Only maps with reactive grass enable its shared player query")
	for bush: Node2D in actual.get("bushes") as Array:
		var solid: StaticBody2D = bush.get_node_or_null("Solid") as StaticBody2D
		check(solid != null and solid.collision_layer == 1 and solid.collision_mask == 0, "Authored bush lower bodies block the world layer")
	for grass: Node2D in actual.get("grasses") as Array:
		check(grass.find_children("*", "CollisionObject2D", true, false).is_empty(), "Reactive grass remains non-blocking")
	print("AUTHORED_VEGETATION trees=%d bushes=%d grasses=%d" % [expected_trees, expected_bushes.size(), expected_grasses])


func _check_bush_physics(raised_bush: Node2D) -> void:
	var bushes: Array = fixture.get("bushes") as Array
	var first: Node2D = bushes[0] as Node2D
	var second: Node2D = bushes[1] as Node2D
	var first_shape: CollisionShape2D = first.get_node("Solid/LowerBody0") as CollisionShape2D
	var second_shape: CollisionShape2D = second.get_node("Solid/LowerBody0") as CollisionShape2D
	check(first_shape.shape is CapsuleShape2D and first_shape.shape == second_shape.shape, "Complete bush stamps share their rounded collision shape")
	check(first.get_meta(&"footprint") == Rect2(2, 8, 28, 24), "Bush lower footprint leaves the upper eight pixels open")
	check(first.position.y == 20.0 and first.z_index == player.z_index, "Bush depth uses the actor plane and authored base")
	var raised_shape: CollisionShape2D = raised_bush.get_node("Solid/LowerBody0") as CollisionShape2D
	check(raised_shape.global_position.is_equal_approx(home + Vector2(256, 20)), "Raised bush collision stays on its logical ground plane")
	await ticks()
	for origin: Vector2 in [Vector2.ZERO, Vector2(160, 0), Vector2(240, 0), Vector2(320, 0)]:
		var label: String = "Bush at " + str(origin)
		check(not player.test_move(Transform2D(0.0, home + origin + Vector2(-20, -1)), Vector2(72, 0)), label + " lets player feet pass through its upper quarter")
		check(player.test_move(Transform2D(0.0, home + origin + Vector2(-20, 12)), Vector2(72, 0)), label + " blocks player motion through its lower body")
		check(player.test_move(Transform2D(0.0, home + origin + Vector2(16, -20)), Vector2(0, 60)), label + " stops downward movement at its lower footprint")
	var partial: Node2D = bushes[3] as Node2D
	check(partial.get_meta(&"footprint") == Rect2(402, 8, 28, 8), "Partial stamp clips its collider to the two painted upper tiles")
	check(player.test_move(Transform2D(0.0, home + Vector2(380, 12)), Vector2(72, 0)), "The painted lower edge of a partial bush is solid")
	check(not player.test_move(Transform2D(0.0, home + Vector2(380, 28)), Vector2(72, 0)), "Erased lower bush tiles leave no invisible collider")
	check(not player.test_move(Transform2D(0.0, home + Vector2(72, -12)), Vector2(0, 60)), "Reactive grass adds no movement-blocking collider")
	var minotaur: CharacterBody2D = MINOTAUR.instantiate() as CharacterBody2D
	minotaur.position = home + Vector2(-160, 160)
	arena.add_child(minotaur)
	minotaur.set_process(false)
	minotaur.set_physics_process(false)
	var spirit: CharacterBody2D = SPIRIT.new() as CharacterBody2D
	spirit.position = home + Vector2(-240, 160)
	arena.add_child(spirit)
	spirit.set_process(false)
	spirit.set_physics_process(false)
	await ticks()
	check(not minotaur.test_move(Transform2D(0.0, home + Vector2(-20, -4)), Vector2(72, 0)), "A terrestrial enemy can pass behind the upper bush edge")
	check(minotaur.test_move(Transform2D(0.0, home + Vector2(-20, 12)), Vector2(72, 0)), "A terrestrial enemy collides with the lower bush body")
	check(spirit.collision_mask == 4 and not spirit.test_move(Transform2D(0.0, home + Vector2(-20, 12)), Vector2(72, 0)), "Wall-phasing spirits retain their intentional passage through bushes")
	minotaur.queue_free()
	spirit.queue_free()
	await ticks()
	print("BUSH_PHYSICS_CHECKED full mirrored raised partial player terrestrial spirit")


func _run() -> void:
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	await create_timer(0.6).timeout
	_check_authored_content()
	player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.get_node("BoosterShooter").set_process(false)
	player.get_node("GameplayKit").process_mode = Node.PROCESS_MODE_DISABLED
	fixture = VEGETATION.new() as Node2D
	fixture.position = home
	arena.add_child(fixture)
	var definitions: Dictionary = {9001: {"relPath": "assets/tiles/floor/bush.png"},
		9002: {"relPath": "assets/tiles/floor/grass_animated1.png"}}
	var partial: Dictionary = layer("PartialBush", 9001, [Vector2(400, 0)], 32)
	partial["gridTiles"] = (partial["gridTiles"] as Array).slice(0, 2)
	var descriptions: Array = [layer("Bushes", 9001, [Vector2.ZERO, Vector2(160, 0)], 32),
		layer("MirroredBush", 9001, [Vector2(320, 0)], 32, true, 1), partial,
		layer("GrassAnimated", 9002, [Vector2(64, 0), Vector2(96, 0)], 16),
		layer("HiddenGrass", 9002, [Vector2(128, 0)], 16, false)]
	var textures: RefCounted = TEXTURES.new()
	fixture.call("build", descriptions, definitions, textures)
	var bushes: Array = fixture.get("bushes") as Array
	var grasses: Array = fixture.get("grasses") as Array
	check(bushes.size() == 4 and grasses.size() == 2, "Complete, mirrored and partial stamps become coherent plants")
	check((bushes[0] as Node2D).find_children("*", "Sprite2D", false, false).size() == 4, "Four 16px bush tiles keep their authored artwork")
	var bush_sprite: Sprite2D = (bushes[0] as Node2D).get_child(0) as Sprite2D
	check((bush_sprite.material as ShaderMaterial).get_shader_parameter(&"asset_palette") == 3, "Bush uses the same violet palette as the tree")
	var raised: Node2D = VEGETATION.new() as Node2D
	raised.position = home
	arena.add_child(raised)
	raised.call("build", [layer("RaisedBush", 9001, [Vector2(240, 0)], 32)], definitions, textures,
		func(_point: Vector2) -> float: return 24.0)
	var raised_bush: Node2D = (raised.get("bushes") as Array)[0] as Node2D
	check(raised_bush.position + (raised_bush.get_child(0) as Sprite2D).position == Vector2(240, -24), "Vegetation artwork projects to the raised plane")
	await _check_bush_physics(raised_bush)
	var grass: Node2D = grasses[0] as Node2D
	var visual: AnimatedSprite2D = grass.get("visual") as AnimatedSprite2D
	var rest_texture: Texture2D = textures.call("get_texture", "assets/tiles/floor/grass_animated1.png") as Texture2D
	check(not visual.is_playing() and visual.sprite_frames.get_frame_texture(visual.animation, visual.frame) == rest_texture, "Default grass is the static grass_animated1 frame")
	check(visual.sprite_frames == (grasses[1].get("visual") as AnimatedSprite2D).sprite_frames, "Grass instances share a single animation resource")
	player.global_position = home + Vector2(56, 4)
	fixture.call("bind_player", player)
	await ticks()
	if rendered: _setup_view()
	await capture("01_idle")
	await move_to(Vector2(68, 4))
	check(int(grass.get("reaction_count")) == 1 and visual.animation == &"rustle", "Player passage triggers one rustle")
	await create_timer(0.12).timeout
	check(visual.sprite_frames.get_frame_texture(visual.animation, visual.frame) != rest_texture, "Rustle advances to the supplied animated frames")
	await capture("02_rustle")
	await create_timer(0.5).timeout
	check(not visual.is_playing() and visual.animation == &"idle" and visual.sprite_frames.get_frame_texture(visual.animation, visual.frame) == rest_texture, "The reaction settles back to grass_animated1")
	await create_timer(0.2).timeout
	check(int(grass.get("reaction_count")) == 1, "Standing on grass does not loop or restart the animation")
	await move_to(Vector2(56, 4))
	await move_to(Vector2(68, 4))
	check(int(grass.get("reaction_count")) == 2, "Leaving and re-entering grass retriggers its reaction")
	await create_timer(0.55).timeout
	await move_to(Vector2(56, 4))
	await move_to(Vector2(90, 4))
	check(int(grass.get("reaction_count")) == 3, "A fast crossing triggers grass even if both frame endpoints are outside it")
	var count_before: int = int(grass.get("reaction_count"))
	await move_to(Vector2(400, 4))
	check(int(grass.get("reaction_count")) == count_before, "A teleport does not react to plants along its skipped path")
	await capture("03_restored")
	await move_to(Vector2(16, -1))
	await capture("04_bush_behind")
	await move_to(Vector2(16, 34))
	await capture("05_bush_front")
	print("VEGETATION_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)


func _setup_view() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/vegetation")
	view = SubViewport.new()
	view.size = Vector2i(640, 320)
	view.world_2d = arena.get_world_2d()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera: Camera2D = Camera2D.new()
	camera.position = home + Vector2(56, 10)
	camera.zoom = Vector2.ONE * 4.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var ground: Polygon2D = Polygon2D.new()
	ground.polygon = PackedVector2Array([home + Vector2(-100, -100), home + Vector2(200, -100), home + Vector2(200, 100), home + Vector2(-100, 100)])
	ground.color = Color("#533048")
	ground.z_index = -90
	arena.add_child(ground)
