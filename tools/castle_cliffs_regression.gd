extends SceneTree
## Recolored castle face, preserved relief/physics and focused rendered views.
## Run headless for assertions, or append -- --capture for visual evidence.

const MAP_FILE: String = "res://monster_booster.ldtk"
const OUTPUT: String = "res://output/castle_cliffs/"
const CLIFF_PATH: String = "assets/tiles/floor/cliff_tileset.png"
const CASTLE_HEIGHT: float = 56.0
const COMPOSITION: Script = preload("res://scripts/dungeon/ldtk_level_composition.gd")
var failures: Array[String] = []
var rendered: bool = false
var arena: Node2D = null
var player: Player = null
var camera: Camera2D = null
var ramps: Array[Rect2] = []
var report: Dictionary = {}


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)


func _level(data: Dictionary, identifier: String) -> Dictionary:
	for entry: Dictionary in data.get("levels", []):
		if str(entry.get("identifier", "")) == identifier:
			return entry
	return {}


func _layer(level: Dictionary, identifier: String) -> Dictionary:
	for entry: Dictionary in level.get("layerInstances", []):
		if str(entry.get("__identifier", "")) == identifier:
			return entry
	return {}


func _restore_elevation_fields(current: Dictionary, before: Dictionary) -> Dictionary:
	var restored: Dictionary = current.duplicate(true)
	for entity: Dictionary in restored.get("entityInstances", []):
		if str(entity.get("__identifier", "")) not in ["ElevationArea", "ElevationRamp"]:
			continue
		var prior: Dictionary = {}
		for old_entity: Dictionary in before.get("entityInstances", []):
			if str(old_entity.get("iid", "")) == str(entity.get("iid", "")):
				prior = old_entity
		for field: Dictionary in entity.get("fieldInstances", []):
			if str(field.get("__identifier", "")) != "HeightPx":
				continue
			check(is_equal_approx(float(field.get("__value", 0)), CASTLE_HEIGHT), "The intended castle area/ramp height is exactly 56 px")
			for old_field: Dictionary in prior.get("fieldInstances", []):
				if str(old_field.get("__identifier", "")) == "HeightPx":
					field["__value"] = old_field.get("__value")
					field["realEditorValues"] = old_field.get("realEditorValues", [])
	return restored


func _elevation_contract(layer: Dictionary) -> Dictionary:
	var result: Dictionary = layer.duplicate()
	var entries: Array = []
	for entity: Dictionary in layer.get("entityInstances", []):
		if str(entity.get("__identifier", "")) in ["ElevationArea", "ElevationRamp"]: entries.append(entity)
	result["entityInstances"] = entries
	return result


func _authored_checks(data: Dictionary) -> void:
	var definition: Dictionary = {}
	for entry: Dictionary in (data.get("defs", {}) as Dictionary).get("tilesets", []):
		if str(entry.get("relPath", "")) == CLIFF_PATH:
			definition = entry
	check(not definition.is_empty(), "The original cliff atlas is registered in LDtk")
	if definition.is_empty():
		return
	check(int(definition.get("tileGridSize", 0)) == 16 and int(definition.get("__cWid", 0)) == 3 and int(definition.get("__cHei", 0)) == 5, "Cliff keeps its native 3 by 5 grid of 16 px pieces")
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path("res://" + CLIFF_PATH))
	check(image != null and image.get_size() == Vector2i(48, 80), "Cliff source PNG retains 48 by 80 pixels without resampling")
	var source: Dictionary = _layer(_level(data, "Room_2_Cenario"), "TerrainFaces")
	check(int(source.get("__tilesetDefUid", -1)) == int(definition.uid), "Castle face uses the recolored original atlas")
	check(int(source.get("pxOffsetY", 0)) == 11 and int(source.get("__pxTotalOffsetY", 0)) == 11, "Face keeps the mapped 11 px projection offset")
	var tiles: Array = source.get("gridTiles", []) as Array
	check(tiles.size() >= 615, "The authored extended face preserves crest, rock and base")
	var scenery: Dictionary = _level(data, "Room_2_Cenario")
	for instance: Dictionary in scenery.get("layerInstances", []):
		if str(instance.get("__type", "")) != "Tiles": continue
		var grid: int = int(instance.get("__gridSize", 16))
		var columns: int = ceili(float(int(scenery.pxWid) - int(instance.get("pxOffsetX", 0))) / grid)
		var rows: int = ceili(float(int(scenery.pxHei) - int(instance.get("pxOffsetY", 0))) / grid)
		check(int(instance.__cWid) == columns and int(instance.__cHei) == rows, "Native editor dimensions include layer offsets: " + str(instance.__identifier))
		for stamp: Dictionary in instance.get("gridTiles", []):
			var editor_index: int = int((stamp.d as Array)[0])
			check(editor_index % columns * grid == int(stamp.px[0]) and floori(float(editor_index) / columns) * grid == int(stamp.px[1]), "Native LDtk tile index matches the runtime position: " + str(instance.__identifier))
	var horizontal_offset: float = float(source.get("__pxTotalOffsetX", 0))
	check(is_equal_approx(horizontal_offset, -160.0), "Left continuation uses valid local cells with an off-map layer offset")
	var used_rows: Dictionary[int, int] = {}
	for tile: Dictionary in tiles:
		var tile_point: Array = tile.px as Array
		var source_point: Array = tile.src as Array
		var tile_y: int = int(tile_point[1])
		used_rows[tile_y] = int(used_rows.get(tile_y, 0)) + 1
		check(int(source_point[0]) in [0, 16, 32] and int(source_point[1]) in [0, 16, 32, 48, 64], "Face paint uses the mapped cliff pieces, including manual contour starts")
		for ramp: Rect2 in ramps:
			check(float(tile_point[0]) + horizontal_offset < ramp.position.x or float(tile_point[0]) + horizontal_offset >= ramp.end.x, "Face artwork leaves the full authored ramp opening clear")
	for expected_row: int in [1008, 1024, 1040, 1056, 1072]:
		check(int(used_rows.get(expected_row, 0)) >= 123, "Each structural face row remains complete")
	var migration_path: String = "res://output/castle_cliffs/edges_migration.json"
	if FileAccess.file_exists(migration_path):
		var migration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(migration_path)) as Dictionary
		var backup_path: String = str(migration.get("backup", ""))
		if not backup_path.is_empty() and FileAccess.file_exists(backup_path):
			var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(backup_path)) as Dictionary
			for level_id: String in ["Room_2", "Room_2_Cenario"]:
				for old_layer: Dictionary in _level(before, level_id).get("layerInstances", []):
					var layer_id: String = str(old_layer.get("__identifier", ""))
					# Floor and decoration remain artist-editable after this historical
					# migration. Only the castle's gameplay/elevation contract is fixed.
					if layer_id in ["Gameplay", "GameplayAreas", "TerrainStairs"]:
						var after_layer: Dictionary = _layer(_level(data, level_id), layer_id)
						var before_layer: Dictionary = old_layer
						if layer_id == "GameplayAreas" and level_id == "Room_2":
							after_layer = _restore_elevation_fields(after_layer, old_layer)
							# The central Warp became CentralWarp after this historical snapshot.
							# Its independent art/relief edits are outside the cliff contract.
							before_layer = _elevation_contract(before_layer)
							after_layer = _elevation_contract(after_layer)
						check(before_layer == after_layer, level_id + "/" + layer_id + " preserves terrain support, elevation geometry and ramp access paint")
	report["atlas_uid"] = int(definition.uid)
	report["atlas_size"] = [48, 80]
	report["face_tiles"] = tiles.size()
	report["rows"] = used_rows


func _read_ramps(layers: Array) -> void:
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) == "ElevationRamp":
				ramps.append(Rect2(Vector2(float(entity.px[0]), float(entity.px[1])), Vector2(float(entity.width), float(entity.height))))
	ramps.sort_custom(func(first: Rect2, second: Rect2) -> bool: return first.position.x < second.position.x)
	check(ramps.size() == 3, "All three authored castle ramps remain present")


func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func _place(point: Vector2) -> void:
	player.global_position = point
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.snap_floor_height()
	player.reset_physics_interpolation()


func _frame(point: Vector2, zoom_level: float) -> void:
	camera.position = point
	camera.zoom = Vector2.ONE * zoom_level
	camera.force_update_scroll()
	camera.reset_physics_interpolation()
	await _settle()


func _capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK, "Rendered view saved: " + label)


func _physics_checks() -> void:
	var elevation: Node2D = arena.get_node("TerrainElevation") as Node2D
	check(is_equal_approx(float(elevation.call("height_at", Vector2(1488, 700))), CASTLE_HEIGHT), "Castle is physically represented at its increased 56 px height")
	check(is_zero_approx(float(elevation.call("height_at", Vector2(1488, 1280)))), "Castle approach remains on the lower plane")
	for index: int in range(ramps.size()):
		var ramp: Rect2 = ramps[index]
		var center_x: float = ramp.get_center().x
		var entry: Vector2 = Vector2(center_x, ramp.end.y + 24.0)
		var summit: Vector2 = Vector2(center_x, ramp.position.y - 24.0)
		check(is_equal_approx(float(elevation.call("height_at", ramp.get_center())), CASTLE_HEIGHT * 0.5), "Ramp " + str(index + 1) + " has a gradual 28 px middle")
		check(not player.test_move(Transform2D(0.0, entry), summit - entry), "Ramp " + str(index + 1) + " has no hidden barrier through its full passage")
		check(player.test_move(Transform2D(0.0, Vector2(ramp.position.x - 32.0, entry.y)), Vector2(0, summit.y - entry.y)), "The ledge beside ramp " + str(index + 1) + " retains the existing physical blocker")
		_place(entry)
		await _settle()
		var hit: KinematicCollision2D = player.move_and_collide(summit - entry)
		check(hit == null and player.global_position.distance_to(summit) < 0.2, "Player really traverses ramp " + str(index + 1) + " from below to the plateau")
		player.snap_floor_height()
		check(is_equal_approx(player.floor_height, CASTLE_HEIGHT), "Player render height follows the summit after crossing ramp " + str(index + 1))
		var back: KinematicCollision2D = player.move_and_collide(entry - summit)
		check(back == null and player.global_position.distance_to(entry) < 0.2, "Player can descend ramp " + str(index + 1))
	var cloud: Node = arena.get_node("TerrainCloudShadows")
	var reference: ShaderMaterial = cloud.get("soil_material") as ShaderMaterial
	var face_count: int = 0
	for node: Node in arena.get_node("LdtkLayers").get_children():
		var surface: TileMapLayer = node as TileMapLayer
		if surface == null or not str(surface.name).begins_with("TerrainFaces"):
			continue
		face_count += 1
		var material: ShaderMaterial = surface.material as ShaderMaterial
		check(surface.z_index == -17 and is_equal_approx(surface.position.y, 11.0), "Cliff face retains its mapped depth and projection")
		check(material != null and reference != null and material.shader == reference.shader and material.get_shader_parameter(&"cloud_elapsed") == reference.get_shader_parameter(&"cloud_elapsed"), "Cliff receives the same coherent cloud shadow clock as the terrain")
		check(int(surface.get_meta(&"asset_palette", 0)) == 5 and material != null and int(material.get_shader_parameter(&"asset_palette")) == 5, "Cliff uses the mountain palette that preserves the solid purple floor background")
	check(face_count == 1, "The face adds one decorative tile layer without creating floor support")
	var rim: TileMapLayer = arena.get_node("LdtkLayers/TerrainCliffRim_0") as TileMapLayer
	check(rim.z_index == -18 and is_equal_approx(rim.position.y, -CASTLE_HEIGHT), "Complete rim follows the elevated plane below the front-facing artwork")
	check(rim.get_used_cells().size() > 250 and rim.material != null, "The full contour is present and receives the terrain material")
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	var rivers: Array[Node2D] = []
	for candidate: Node2D in water.regions:
		if str(candidate.get_meta(&"preset", "")) == "River": rivers.append(candidate)
	check(rivers.size() == 1 and water.diagnostics.is_empty(), "River remains one continuous region alongside independent sea areas")
	if rivers.is_empty(): return
	var region: Node2D = rivers[0]
	check(bool(region.get_meta(&"terrain_clipped", false)), "River opts into clipping against logical terrain")
	var mask: Image = (region.get_node("Surface") as Sprite2D).texture.get_image()
	var rect: Rect2 = region.get_meta(&"authored_rect") as Rect2
	check(mask.get_size() == Vector2i(688, 3312), "Coastline mask preserves native single-pixel atlas edges")
	check(mask.get_format() == Image.FORMAT_LA8, "The native mask needs only two channels without mipmaps")
	for point: Vector2 in [Vector2(2559, 900), Vector2(2559, 800)]:
		check(mask.get_pixelv(Vector2i(point - rect.position)).a8 == 255, "Water reaches the transparent outside pixels of the cliff: " + str(point))
	check(mask.get_pixelv(Vector2i(Vector2(2545, 900) - rect.position)).a8 == 0, "Opaque cliff interior retains its solid ground color")
	var coast_cell: Vector2i = Vector2i(159, 59)
	check((arena.get("_floor_cells") as Dictionary).has(coast_cell), "Replacing square floor artwork preserves its physical support")
	var drawn_square: bool = false
	for child: Node in arena.get_node("LdtkLayers").get_children():
		var floor_layer: TileMapLayer = child as TileMapLayer
		if floor_layer != null and str(child.name).begins_with("Floor_"):
			drawn_square = drawn_square or floor_layer.get_cell_source_id(coast_cell) >= 0
	check(not drawn_square, "No square floor tile renders behind the transparent cliff rim")
	for point: Vector2 in [Vector2(2448, 1086), Vector2(2512, 1086), Vector2(2448, 1104)]:
		var sample: Vector2i = Vector2i(((point - rect.position) / rect.size * Vector2(mask.get_size())).floor())
		check(mask.get_pixelv(sample).a8 == 0, "Water cannot show through the cliff foot or lower ground: " + str(point))
	var river_sample: Vector2i = Vector2i(((Vector2(2592, 1086) - rect.position) / rect.size * Vector2(mask.get_size())).floor())
	check(mask.get_pixelv(river_sample).a8 == 255, "The actual river at the low level stays visible")
	report["water_mask_bytes"] = mask.get_data().size()
	report["rim_tiles"] = rim.get_used_cells().size()


func _render_views() -> void:
	if not rendered:
		return
	for index: int in range(ramps.size()):
		var ramp: Rect2 = ramps[index]
		_place(Vector2(ramp.get_center().x, ramp.get_center().y - 3.0))
		await _frame(Vector2(ramp.get_center().x, 1080), 3.0)
		await _capture("0" + str(index + 1) + "_access_" + str(index + 1))
	_place(Vector2(1760, 1160))
	await _frame(Vector2(1784, 1076), 3.0)
	await _capture("04_rock_face_lighting")
	var lighting: CanvasLayer = arena.get_node("RoomLighting") as CanvasLayer
	lighting.hide()
	await _settle()
	await _capture("05_rock_face_palette")
	lighting.show()
	var chosen: Rect2 = ramps[1]
	for stage: int in range(3):
		var point: Vector2 = Vector2(chosen.get_center().x, chosen.end.y + 16.0 - float(stage) * 88.0 - 3.0)
		_place(point)
		player.body.set_motion(Vector2.UP)
		await _frame(Vector2(chosen.get_center().x, 1096), 3.0)
		await _capture("0" + str(stage + 6) + "_ascent_" + str(stage + 1))
	player.body.set_motion(Vector2.ZERO)
	_place(Vector2(1488, 700))
	await _frame(Vector2(1384, 596), 0.45)
	await _capture("09_castle_overview_lighting")
	lighting.hide()
	await _settle()
	await _capture("10_castle_overview_palette")
	lighting.show()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1200, 800)
	root.content_scale_size = Vector2i(1200, 800)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_FILE)) as Dictionary
	var composition: Dictionary = COMPOSITION.compose(data, "Room_2")
	_read_ramps(composition.layers as Array)
	_authored_checks(data)
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	var deadline: int = Time.get_ticks_msec() + 5000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(arena.get("entry_complete")), "Open world loads successfully with arrival beam disabled for inspection")
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	for layer_name: String in ["PlayerHUD", "ArenaUI"]:
		var overlay: CanvasLayer = arena.get_node_or_null(layer_name) as CanvasLayer
		if overlay != null:
			overlay.hide()
	camera = Camera2D.new()
	camera.name = "CliffInspectionCamera"
	camera.position_smoothing_enabled = false
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arena.add_child(camera)
	camera.make_current()
	await _settle()
	await _physics_checks()
	await _render_views()
	report["ramps"] = ramps.size()
	report["height_px"] = CASTLE_HEIGHT
	report["rendered"] = rendered
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var stream: FileAccess = FileAccess.open(OUTPUT + ("render_report.json" if rendered else "headless_report.json"), FileAccess.WRITE)
	if stream != null:
		stream.store_string(JSON.stringify(report, "\t") + "\n")
		stream.close()
	print("CASTLE_CLIFFS_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)
