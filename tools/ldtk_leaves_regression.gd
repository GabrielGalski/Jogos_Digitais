extends "res://tools/ldtk_direct_sprites_regression.gd"

const LEAVES: Script = preload("res://scripts/dungeon/ldtk_leaves.gd")


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var fixture: Dictionary = data.duplicate(true)
	var level: Dictionary = (fixture.levels as Array)[0]
	level.pxWid = 480
	level.pxHei = 256
	for layer: Dictionary in level.layerInstances:
		layer.gridTiles = []
		layer.autoLayerTiles = []
		layer.entityInstances = []
		layer.__cWid = 30
		layer.__cHei = 16
		layer.intGridCsv = []
		if str(layer.__type) == "IntGrid":
			var empty_cells: Array = []
			empty_cells.resize(480)
			empty_cells.fill(0)
			layer.intGridCsv = empty_cells
	_build_fixture(fixture)
	for layer: Dictionary in level.layerInstances:
		if str(layer.__identifier) == "Entities":
			layer.entityInstances = []
		elif str(layer.__identifier) == "Gameplay":
			(layer.intGridCsv as Array).fill(0)
		elif str(layer.__identifier) == "Leaves":
			_stamp(layer.gridTiles, Vector2i(64, 32), Rect2i(0, 48, 128, 80), 0)
			_stamp(layer.gridTiles, Vector2i(176, 32), Rect2i(176, 48, 80, 128), 0)
			_stamp(layer.gridTiles, Vector2i(0, 0), Rect2i(0, 48, 128, 80), 3)
	var arena: Node2D = await _open_fixture(fixture, "leaves")
	var player: Player = arena.get_node("Nox") as Player
	var foreground: Node2D = arena.get_node("ForegroundLeaves") as Node2D
	assert(not foreground.z_as_relative and foreground.z_index == LEAVES.FOREGROUND_Z)
	assert(not foreground.y_sort_enabled, "Folhas mudam de ordem com o Y")
	assert(get_nodes_in_group("ldtk_leaves").size() == 3, "Folhas deveriam ser agrupadas por stamp")
	assert(foreground.find_children("*", "Light2D", true, false).is_empty(), "Folhas ainda projetam luz")
	assert(foreground.find_children("*", "CollisionObject2D", true, false).is_empty(), "Folhas afetam fisica")
	assert(foreground.find_children("*", "CollisionShape2D", true, false).is_empty(), "Folhas possuem colisao")
	for patch: Node2D in get_nodes_in_group("ldtk_leaves"):
		assert(not patch.has_node("LilacHalo"), "Folhas ainda possuem halo")
		for child: Node in patch.get_children():
			if child is Sprite2D:
				assert((child as Sprite2D).texture is ImageTexture, "Folhas nao usam PNG vivo")
				assert((child as Sprite2D).texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	for prop: Node2D in get_nodes_in_group("ldtk_map_volumes"):
		assert(prop.z_index < foreground.z_index)
	assert(player.z_index < foreground.z_index)
	player.position = Vector2(100, 88)
	player.reset_physics_interpolation()
	var health: float = player.health
	assert(not player.test_move(player.global_transform, Vector2(50, 0)), "Folhas bloqueiam passagem")
	_key(KEY_D, true)
	await create_timer(0.5).timeout
	_key(KEY_D, false)
	assert(player.position.x > 140, "Nox nao atravessou folhas")
	assert(is_equal_approx(player.health, health), "Folhas tiraram vida")
	var projectiles: Node = arena.get_node("ManifestationProjectiles")
	var shots_before: int = projectiles.get_child_count()
	arena.get_node("ManifestationController").call("_fire")
	assert(projectiles.get_child_count() == shots_before + 1)
	await _check_texture_refresh()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_leaves(arena)
	print("LDTK LEAVES PASS: foreground over props/actors, no physics or projected light/halo, walking/shooting, flips and live PNG")
	quit(0)


func _stamp(tiles: Array, at: Vector2i, region: Rect2i, flip: int) -> void:
	var columns: int = floori(float(region.size.x) / 16.0)
	var rows: int = floori(float(region.size.y) / 16.0)
	for y: int in range(rows):
		for x: int in range(columns):
			var sx: int = columns - x - 1 if (flip & 1) != 0 else x
			var sy: int = rows - y - 1 if (flip & 2) != 0 else y
			var tile: Dictionary = _tile(at + Vector2i(x, y) * 16, region.position + Vector2i(sx, sy) * 16, 16)
			tile.f = flip
			tiles.append(tile)


func _capture_leaves(arena: Node2D) -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	var player: Player = arena.get_node("Nox") as Player
	player.intro_locked = true
	player.position = Vector2(130, 92)
	player.reset_physics_interpolation()
	(player.get_node("Camera2D") as Camera2D).enabled = false
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(160, 80)
	camera.zoom = Vector2.ONE * 1.4
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arena.add_child(camera)
	camera.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://renders")
	var foreground: Node2D = arena.get_node("ForegroundLeaves") as Node2D
	# Bright world prop directly beneath opaque leaves must be occluded, not
	# merely darkened. This also guards against accidental Y-sort regressions.
	var probe: Polygon2D = Polygon2D.new()
	probe.position = Vector2(120, 88)
	probe.polygon = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])
	probe.color = Color.WHITE
	probe.z_as_relative = false
	probe.z_index = 900
	var probe_material: CanvasItemMaterial = CanvasItemMaterial.new()
	probe_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	probe.material = probe_material
	arena.add_child(probe)
	await process_frame
	await RenderingServer.frame_post_draw
	var screen: Vector2 = (probe.position - camera.position) * camera.zoom * 2.0 + Vector2(root.size) * 0.5
	var covered_pixel: Color = root.get_texture().get_image().get_pixel(floori(screen.x), floori(screen.y))
	foreground.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var uncovered_pixel: Color = root.get_texture().get_image().get_pixel(floori(screen.x), floori(screen.y))
	assert(uncovered_pixel.is_equal_approx(Color.WHITE), "Probe de oclusao fora do pixel esperado")
	assert(covered_pixel.r < 0.5 and covered_pixel.g < 0.5, "Folhas nao cobrem prop de primeiro plano")
	probe.queue_free()
	foreground.show()
	await process_frame
	await RenderingServer.frame_post_draw
	var with_leaves: Image = root.get_texture().get_image()
	assert(with_leaves.save_png("res://renders/ldtk_leaves.png") == OK)
	foreground.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_leaves: Image = root.get_texture().get_image()
	assert(without_leaves.save_png("res://renders/ldtk_leaves_uncovered.png") == OK)
	assert(with_leaves.get_data() != without_leaves.get_data(), "Folhas nao apareceram na renderizacao")
	foreground.show()
