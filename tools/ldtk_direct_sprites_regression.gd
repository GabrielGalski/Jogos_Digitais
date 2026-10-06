extends SceneTree

const ARENA: PackedScene = preload("res://scenes/dungeon/ldtk_arena.tscn")
const TEXTURE_SOURCE: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
var _falls: int = 0
var _ends: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var map_file: FileAccess = FileAccess.open("res://monster_booster.ldtk", FileAccess.READ)
	assert(map_file != null)
	var data: Dictionary = JSON.parse_string(map_file.get_as_text()) as Dictionary
	var wall_sources: int = 0
	for source: Dictionary in (data.defs as Dictionary).tilesets:
		assert(not str(source.relPath).contains("/editor/"), "LDtk ainda usa uma copia de paleta")
		if str(source.relPath).ends_with("wall_tileset.png"):
			wall_sources += 1
	assert(wall_sources == 1, "Mais de um tileset para a parede")
	assert((data.levels as Array).size() == 1, "Mapas antigos ainda presentes")
	await _check_texture_refresh()
	assert(change_scene_to_file("res://scenes/dungeon/ldtk_arena.tscn") == OK)
	await create_timer(0.55).timeout
	var player: Player = current_scene.get_node("Nox") as Player
	assert(player != null and not player.intro_locked, "Mapa autoral nao aceita preview")
	var fixture: Dictionary = data.duplicate(true)
	_build_fixture(fixture)
	var arena: Node2D = await _open_fixture(fixture, "entity")
	player = arena.get_node("Nox") as Player
	var gameplay: Node2D = arena.get_node("Gameplay") as Node2D
	gameplay.connect("player_fell", func(_body: Node2D) -> void: _falls += 1)
	gameplay.connect("end_reached", func(_body: Node2D) -> void: _ends += 1)
	assert(player.respawn_position.is_equal_approx(Vector2(104, 88)), "Start nao configurou respawn")
	var columns: int = 0
	for volume: Node in get_nodes_in_group("ldtk_map_volumes"):
		if str(volume.get_meta("kind", "")).begins_with("column"):
			columns += 1
		for child: Node in volume.get_children():
			if child is Sprite2D:
				assert((child as Sprite2D).texture is ImageTexture, "Volume nao usa PNG vivo")
	assert(columns == 2, "Colunas diretas nao agrupadas")
	var space: PhysicsDirectSpaceState2D = arena.get_world_2d().direct_space_state
	assert(_solid_at(space, player, Vector2(232, 44)), "Parede direta nao bloqueia")
	assert(_solid_at(space, player, Vector2(188, 130)), "Coluna quadrada sem base")
	assert(_solid_at(space, player, Vector2(252, 130)), "Coluna redonda sem base")
	assert(_solid_at(space, player, Vector2(24, 24)), "MapLimit sem colisao")
	assert(not _solid_at(space, player, Vector2(296, 24)), "DoorBlock deveria iniciar aberto")
	gameplay.call("set_doors_locked", true)
	await physics_frame
	await physics_frame
	assert(_solid_at(space, player, Vector2(296, 24)), "DoorBlock nao fecha")
	gameplay.call("set_doors_locked", false)
	var health: float = player.health
	_key(KEY_D, true)
	await create_timer(0.5).timeout
	_key(KEY_D, false)
	assert(_falls > 0 and player.position.x < 128.0, "Andar permite atravessar DoorDash")
	assert(is_equal_approx(player.health, health), "Queda tirou vida")
	player.position = Vector2(116, 88)
	player.dash_recovery = 0.0
	player.reset_physics_interpolation()
	assert(player.try_dash(Vector2.RIGHT))
	var falls_before: int = _falls
	await create_timer(0.22).timeout
	assert(player.position.x > 160.0 and _falls == falls_before, "Dash nao atravessa o vao")
	assert(_ends > 0, "End nao detecta travessia")
	player.position = Vector2(116, 88)
	player.dash_duration = 0.055
	player.dash_recovery = 0.0
	player.reset_physics_interpolation()
	assert(player.try_dash(Vector2.RIGHT))
	await create_timer(0.2).timeout
	assert(_falls > falls_before and player.position.is_equal_approx(player.respawn_position), "Terminar dash no vao nao retorna ao Start")
	player.dash_duration = 0.16
	player.position = Vector2(232, 70)
	player.dash_recovery = 0.0
	assert(player.try_dash(Vector2.UP))
	await create_timer(0.2).timeout
	assert(player.position.y >= 48.0, "Dash atravessou parede normal")
	var projectiles: Node2D = arena.get_node("ManifestationProjectiles") as Node2D
	var count: int = projectiles.get_child_count()
	arena.get_node("ManifestationController").call("_fire")
	assert(projectiles.get_child_count() == count + 1, "Disparo da sala de treino foi removido")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(arena)
	# Same gap without entity, painted in Gameplay and without Floor underneath.
	var level: Dictionary = (fixture.levels as Array)[0]
	for layer: Dictionary in level.layerInstances:
		if str(layer.__identifier) == "Entities":
			layer.entityInstances = []
		elif str(layer.__identifier) == "Gameplay":
			for y: int in range(3, 7):
				for x: int in range(8, 10):
					(layer.intGridCsv as Array)[y * 30 + x] = 2
		elif str(layer.__identifier) == "Floor":
			var kept: Array = []
			for tile: Dictionary in layer.gridTiles:
				if not Rect2(128, 48, 32, 64).has_point(Vector2(float(tile.px[0]), float(tile.px[1]))):
					kept.append(tile)
			layer.gridTiles = kept
	arena = await _open_fixture(fixture, "intgrid")
	player = arena.get_node("Nox") as Player
	player.position = Vector2(116, 88)
	assert(player.try_dash(Vector2.RIGHT))
	await create_timer(0.22).timeout
	assert(player.position.x > 160.0, "Contorno do Floor bloqueou o DashGap sem piso")
	print("LDTK DIRECT SPRITES / DOOR DASH PASS: hot reload, wall/columns, walking fall, dash crossing, expired dash, Start/End, door locks, shooting")
	assert(change_scene_to_file("res://scenes/merchant_corridor.tscn") == OK)
	await process_frame
	await process_frame
	current_scene.call("_restart_corridor")
	await create_timer(1.0).timeout
	assert(current_scene.scene_file_path == "res://scenes/dungeon/ldtk_arena.tscn", "Hall nao abre o novo mapa")
	print("Merchant hall -> authored LDtk map PASS")
	quit(0)


func _check_texture_refresh() -> void:
	DirAccess.make_dir_recursive_absolute("res://tmp")
	var path: String = "res://tmp/direct_sprite_refresh_fixture.png"
	var source: Image = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	source.fill(Color.RED)
	assert(source.save_png(path) == OK)
	var textures: RefCounted = TEXTURE_SOURCE.new()
	var texture: Texture2D = textures.call("get_texture", path) as Texture2D
	assert(texture != null and texture.get_image().get_pixel(0, 0).is_equal_approx(Color.RED))
	source.fill(Color.GREEN)
	assert(source.save_png(path) == OK)
	assert(int(textures.call("refresh")) == 1, "Mudanca no PNG nao atualizou")
	await process_frame
	await process_frame
	var updated: Image = textures.call("get_source_image", path) as Image
	assert(updated.get_pixel(0, 0).is_equal_approx(Color.GREEN), "PNG vivo ficou antigo")
	# The headless dummy renderer cannot read back GPU updates. Real rendering
	# additionally checks the updated texture, not only the source CPU image.
	if DisplayServer.get_name() != "headless":
		assert(texture.get_image().get_pixel(0, 0).is_equal_approx(Color.GREEN), "Textura GPU ficou antiga")
	assert(textures.call("get_texture", path) == texture, "Hot reload trocou a referencia compartilhada")


func _build_fixture(data: Dictionary) -> void:
	var level: Dictionary = (data.levels as Array)[0]
	# Tests use a private, deterministic canvas, never assumptions about the
	# author's current drawing or dimensions, and never rewrite the real map.
	level.pxWid = 480
	level.pxHei = 256
	for layer: Dictionary in level.layerInstances:
		var layer_grid: int = int(layer.get("__gridSize", 16))
		layer.__cWid = floori(480.0 / layer_grid)
		layer.__cHei = floori(256.0 / layer_grid)
		layer.gridTiles = []
		layer.autoLayerTiles = []
		layer.entityInstances = []
		layer.intGridCsv = []
		if str(layer.__type) == "IntGrid":
			var empty_cells: Array = []
			empty_cells.resize(int(layer.__cWid) * int(layer.__cHei))
			empty_cells.fill(0)
			layer.intGridCsv = empty_cells
	for layer: Dictionary in level.layerInstances:
		match str(layer.__identifier):
			"Floor":
				for y: int in range(10):
					for x: int in range(20):
						(layer.gridTiles as Array).append(_tile(Vector2i(x * 16, y * 16), Vector2i(16, 16), 4))
			"WallsBack":
				var wall_grid: int = int(layer.get("__gridSize", 16))
				for y: int in range(floori(48.0 / wall_grid)):
					for x: int in range(floori(64.0 / wall_grid)):
						(layer.gridTiles as Array).append(_tile(Vector2i(224 + x * wall_grid, y * wall_grid), Vector2i(192 + x * wall_grid, 16 + y * wall_grid), floori(256.0 / wall_grid), wall_grid))
			"ObjectsBackSquare", "ObjectsBackRound":
				var at: Vector2i = Vector2i(176 if str(layer.__identifier).ends_with("Square") else 240, 80)
				for y: int in range(4):
					for x: int in range(2):
						(layer.gridTiles as Array).append(_tile(at + Vector2i(x, y) * 16, Vector2i(x, y) * 16, 2))
			"Gameplay":
				(layer.intGridCsv as Array)[5 * 30 + 6] = 4
				(layer.intGridCsv as Array)[5 * 30 + 10] = 5
				(layer.intGridCsv as Array)[1 * 30 + 1] = 1
				(layer.intGridCsv as Array)[1 * 30 + 18] = 3
			"Entities":
				layer.entityInstances = [{"__identifier": "DoorDash", "__type": "DoorDash", "px": [128, 48], "width": 32, "height": 64, "__pivot": [0, 0]}]


func _tile(pixel: Vector2i, source: Vector2i, columns: int, grid: int = 16) -> Dictionary:
	return {"px": [pixel.x, pixel.y], "src": [source.x, source.y], "f": 0, "t": floori(float(source.y) / grid) * columns + floori(float(source.x) / grid), "d": [], "a": 1}


func _open_fixture(data: Dictionary, label: String) -> Node2D:
	var path: String = "res://tmp/door_dash_" + label + ".ldtk"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	if current_scene != null:
		current_scene.free()
	var arena: Node2D = ARENA.instantiate() as Node2D
	arena.set("map_path", path)
	root.add_child(arena)
	current_scene = arena
	await create_timer(0.6).timeout
	return arena


func _solid_at(space: PhysicsDirectSpaceState2D, player: Player, point: Vector2) -> bool:
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	return not space.intersect_point(query).is_empty()


func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _capture(arena: Node2D) -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	var player: Player = arena.get_node("Nox") as Player
	player.intro_locked = true
	player.position = Vector2(116, 88)
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
	assert(root.get_texture().get_image().save_png("res://renders/ldtk_door_dash.png") == OK)
