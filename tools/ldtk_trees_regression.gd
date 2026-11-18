extends SceneTree
## Real actor sweeps plus rendered, pixel-checked front/behind cases.

const TREES: Script = preload("res://scripts/dungeon/ldtk_trees.gd")
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
const GHOST: Script = preload("res://scripts/enemies/spirit_ghost.gd")
const DESTINATION: String = "res://output/tree_mapping/"
var failures: Array[String] = []
var arena: Node2D = null
var fixture: Node2D = null
var player: Player = null
var enemy: CharacterBody2D = null
var ghost: CharacterBody2D = null
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


func layer(origin: Vector2, flip: int = 0, rows: int = 5, shown: bool = true) -> Dictionary:
	var tiles: Array[Dictionary] = []
	for y: int in range(rows):
		for x: int in range(5):
			var source: Vector2 = Vector2(x, y) * 16.0
			var mirrored: Vector2 = source
			if (flip & 1) != 0: mirrored.x = 64.0 - source.x
			if (flip & 2) != 0: mirrored.y = 64.0 - source.y
			var pixel: Vector2 = origin + mirrored
			tiles.append({"src": [source.x, source.y], "px": [pixel.x, pixel.y], "f": flip, "a": 1.0})
	return {"__identifier": "Trees", "iid": str(origin), "__tilesetDefUid": 624, "visible": shown,
		"__gridSize": 16, "__opacity": 1.0, "gridTiles": tiles, "autoLayerTiles": []}


func tree_at(origin: Vector2) -> Node2D:
	for tree: Node2D in fixture.get_children():
		if (tree.get_meta(&"authored_origin") as Vector2).is_equal_approx(origin): return tree
	return null


func ticks() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func _run() -> void:
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	await create_timer(0.6).timeout
	player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.body.stop()
	player.get_node("GameplayKit").process_mode = Node.PROCESS_MODE_DISABLED
	player.get_node("BoosterShooter").set_process(false)
	fixture = TREES.new() as Node2D
	fixture.position = home
	arena.add_child(fixture)
	var descriptions: Array = [layer(Vector2.ZERO), layer(Vector2(160, 0), 1), layer(Vector2(320, 0), 2),
		layer(Vector2(480, 0), 3), layer(Vector2(640, 0), 0, 4), layer(Vector2(800, 0), 0, 5, false), layer(Vector2(960, 0))]
	fixture.call("build", descriptions, {624: {"relPath": "assets/tiles/floor/tree.png"}}, TEXTURES.new(),
		func(point: Vector2) -> float: return 24.0 if point.x > home.x + 900 else 0.0)
	check(fixture.get_child_count() == 6, "Stamp grouping produces one tree per painted origin; hidden layer is ignored")
	for x: int in [0, 160, 320, 480]:
		var tree: Node2D = tree_at(Vector2(x, 0))
		check(tree != null and tree.has_node("Trunk/RootFootprint"), "Whole stamp creates exactly one solid trunk")
		check(tree.z_index == player.z_index and not tree.y_sort_enabled and fixture.y_sort_enabled, "Whole tree shares the actors' Y-sort band")
	check(not tree_at(Vector2(640, 0)).has_node("Trunk"), "A canopy-only stamp has no invisible trunk")
	check(float(tree_at(Vector2(960, 0)).get_meta(&"projected_height")) == 24.0, "Raised trees project visually without moving their collision plane")
	var flipped: StaticBody2D = tree_at(Vector2(320, 0)).get_node("Trunk") as StaticBody2D
	check(flipped.global_position.is_equal_approx(home + Vector2(360, 10)), "Vertical flip also mirrors the root footprint")
	var collider: CollisionShape2D = tree_at(Vector2.ZERO).get_node("Trunk/RootFootprint") as CollisionShape2D
	var first_sprite: Sprite2D = tree_at(Vector2.ZERO).get_child(0) as Sprite2D
	check((first_sprite.material as ShaderMaterial).get_shader_parameter(&"asset_palette") == 3, "Tree material selects the violet source-palette replacement")
	var capsule: CapsuleShape2D = collider.shape as CapsuleShape2D
	check(capsule.radius == 6.0 and capsule.height == 24.0, "Root mapping is a 24x12 horizontal capsule")
	enemy = (load("res://scenes/enemies/minotaur.tscn") as PackedScene).instantiate() as CharacterBody2D
	enemy.position = home + Vector2(-200, -200)
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	(enemy.get_node("Sprite") as AnimatedSprite2D).stop()
	ghost = GHOST.new() as CharacterBody2D
	arena.get_node("SpiritHordes").get_child(0).add_child(ghost)
	ghost.global_position = home + Vector2(-300, -200)
	ghost.set_process(false)
	await ticks()
	check(player.test_move(Transform2D(0.0, home + Vector2(40, 40)), Vector2(0, 50)), "Player is blocked by the lower trunk")
	check(not player.test_move(Transform2D(0.0, home + Vector2(40, -5)), Vector2(0, 48)), "Player can walk underneath the upper canopy")
	check(not player.test_move(Transform2D(0.0, home + Vector2(12, -5)), Vector2(0, 100)), "Side passage is not blocked by the wide crown")
	check(enemy.test_move(Transform2D(0.0, home + Vector2(40, 30)), Vector2(0, 60)), "Grounded enemy is blocked by the lower trunk")
	check(not ghost.test_move(Transform2D(0.0, home + Vector2(40, 30)), Vector2(0, 60)), "Wall-phasing spirit keeps its existing movement mask")
	check(ghost.collision_mask == 4, "Tree integration does not change ghost phasing")
	check((arena.get_node("SpiritHordes") as Node2D).y_sort_enabled and (ghost.get_parent() as Node2D).y_sort_enabled, "Nested encounter actors participate in world Y sorting")
	var clouds: Node = preload("res://scripts/visual/terrain_cloud_shadows.gd").new() as Node
	root.add_child(clouds)
	var surfaces: Array[TileMapLayer] = []
	for palette: int in [0, 1, 2, 1]:
		var surface: TileMapLayer = TileMapLayer.new()
		surface.set_meta(&"asset_palette", palette)
		root.add_child(surface)
		surfaces.append(surface)
	clouds.call("configure", load("res://resources/visual/terrain/open_world_soil.tres"), surfaces)
	clouds.set_physics_process(false)
	clouds.call("set_elapsed", 12.5)
	check(surfaces[1].material == surfaces[3].material and surfaces[0].material != surfaces[1].material, "Materials are shared per ground palette, without recoloring the original atlas")
	for surface: TileMapLayer in surfaces:
		var material: ShaderMaterial = surface.material as ShaderMaterial
		check(float(material.get_shader_parameter(&"cloud_elapsed")) == 12.5, "Grass and stone receive the same continuous cloud time")
	_boundary_stamps()
	if rendered:
		await _visual_checks()
	print("LDTK_TREES_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)


func _boundary_stamps() -> void:
	var boundary: Node2D = TREES.new() as Node2D
	boundary.position = home + Vector2(1400, 0)
	arena.add_child(boundary)
	var descriptions: Array = []
	for entry: Array in [[Vector2(112, 16), 0, false], [Vector2(112, 16), 1, false],
		[Vector2(32, 112), 0, false], [Vector2(112, 16), 0, true]]:
		var description: Dictionary = layer(entry[0] as Vector2, int(entry[1]))
		description.iid = str(entry)
		description["__cWid"] = 8
		description["__cHei"] = 8
		var clipped: Array[Dictionary] = []
		for tile: Dictionary in description.gridTiles:
			var point: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1]))
			if not Rect2(0, 0, 128, 128).has_point(point): continue
			# This source cell is opaque and inside the level: an artist erased it.
			if bool(entry[2]) and tile.src == [0.0, 16.0]: continue
			clipped.append(tile)
		description.gridTiles = clipped
		descriptions.append(description)
	boundary.call("build", descriptions, {624: {"relPath": "assets/tiles/floor/tree.png"}}, TEXTURES.new())
	check(boundary.get_child_count() == 4, "Boundary stamps remain distinct, including mirrored and deliberately erased selections")
	for index: int in range(boundary.get_child_count()):
		var tree: Node2D = boundary.get_child(index) as Node2D
		if index == 3:
			check(not bool(tree.get_meta(&"boundary_completed")) and not tree.has_node("Trunk"), "An erased cell inside the map prevents exterior stamp completion")
		else:
			check(bool(tree.get_meta(&"boundary_completed")) and tree.has_node("Trunk/RootFootprint"), "Clipped complete stamp restores its exterior crown and root")
			check(tree.get_child_count() == 2 and not (tree.get_child(0) as Sprite2D).region_enabled, "One complete sprite renders across the map boundary without a tile crop")
	boundary.queue_free()


func frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func difference(first: Image, second: Image) -> int:
	var changed: int = 0
	for y: int in range(first.get_height()):
		for x: int in range(first.get_width()):
			if first.get_pixel(x, y).to_rgba32() != second.get_pixel(x, y).to_rgba32(): changed += 1
	return changed


func _visual_checks() -> void:
	DirAccess.make_dir_recursive_absolute(DESTINATION)
	# Let the real minotaur's arrival fade finish before pixel comparisons.
	await create_timer(0.4).timeout
	view = SubViewport.new()
	view.size = Vector2i(160, 144)
	view.world_2d = arena.get_world_2d()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera: Camera2D = Camera2D.new()
	camera.position = home + Vector2(40, 48)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var background: Polygon2D = Polygon2D.new()
	background.color = Color("#362030")
	background.z_index = -100
	background.polygon = PackedVector2Array([home + Vector2(-80, -80), home + Vector2(120, -80), home + Vector2(120, 160), home + Vector2(-80, 160)])
	arena.add_child(background)
	for actor: Node2D in [player, enemy, ghost]: actor.hide()
	var baseline: Image = await frame()
	baseline.save_png(DESTINATION + "tree_only.png")
	for index: int in range(3):
		var actor: Node2D = [player, enemy, ghost][index] as Node2D
		var label: String = ["nox", "minotaur", "spirit"][index]
		actor.global_position = home + Vector2(40, 35)
		actor.reset_physics_interpolation()
		actor.show()
		var behind: Image = await frame()
		var hidden_pixels: int = difference(baseline, behind)
		check(hidden_pixels < 5, "Upper crown occludes " + label + " (visible delta " + str(hidden_pixels) + ")")
		behind.resize(640, 576, Image.INTERPOLATE_NEAREST)
		behind.save_png(DESTINATION + label + "_behind.png")
		# Teleport for a deliberate overlap sample; collision was swept separately.
		actor.global_position = home + Vector2(40, 72)
		actor.reset_physics_interpolation()
		var front: Image = await frame()
		var visible_pixels: int = difference(baseline, front)
		check(visible_pixels > 20, "Lower/front position reveals " + label)
		tree_at(Vector2.ZERO).hide()
		var actor_only: Image = await frame()
		actor.hide()
		var empty: Image = await frame()
		tree_at(Vector2.ZERO).show()
		var covering_pixels: int = 0
		for y: int in range(front.get_height()):
			for x: int in range(front.get_width()):
				var background_pixel: int = empty.get_pixel(x, y).to_rgba32()
				var actor_pixel: int = actor_only.get_pixel(x, y).to_rgba32()
				if baseline.get_pixel(x, y).to_rgba32() != background_pixel and actor_pixel != background_pixel:
					if front.get_pixel(x, y).to_rgba32() == actor_pixel: covering_pixels += 1
		check(covering_pixels > 5, "Front actor paints above overlapping tree pixels: " + label)
		front.resize(640, 576, Image.INTERPOLATE_NEAREST)
		front.save_png(DESTINATION + label + "_front.png")
		actor.hide()
