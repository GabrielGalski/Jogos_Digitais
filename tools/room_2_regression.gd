extends SceneTree
## Map geometry and idle pedestal arenas; no automatic exploration populations.

var failures: Array[String] = []
var rendered: bool = false
var arena: Node2D = null
var player: Player = null
var authored_size: Vector2 = Vector2.ZERO


func _bridge_components(layers: Array) -> Array[Rect2]:
	var cells: Dictionary[Vector2i, bool] = {}
	for layer: Dictionary in layers:
		if str(layer.get("__identifier", "")) != "Floor_Bridges" or not bool(layer.get("visible", true)):
			continue
		for tile: Dictionary in layer.get("gridTiles", []):
			cells[Vector2i((Vector2(float(tile.px[0]), float(tile.px[1])) / 16.0).floor())] = true
	var components: Array[Rect2] = []
	while not cells.is_empty():
		var first: Vector2i = cells.keys()[0] as Vector2i
		var pending: Array[Vector2i] = [first]
		var bounds: Rect2i = Rect2i(first, Vector2i.ONE)
		cells.erase(first)
		while not pending.is_empty():
			var cell: Vector2i = pending.pop_back() as Vector2i
			bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
			for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var neighbor: Vector2i = cell + direction
				if cells.has(neighbor):
					cells.erase(neighbor)
					pending.append(neighbor)
		components.append(Rect2(Vector2(bounds.position * 16), Vector2(bounds.size * 16)))
	components.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y)
	return components


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func wait_until(condition: Callable, seconds: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://output/room_2")
	root.get_texture().get_image().save_png("res://output/room_2/" + label + ".png")


func place(point: Vector2) -> void:
	player.global_position = point
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.snap_floor_height()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	player.reset_physics_interpolation()


func _run() -> void:
	root.size = Vector2i(960, 540)
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var composition: Dictionary = preload("res://scripts/dungeon/ldtk_level_composition.gd").compose(data, "Room_2")
	var entities: Array[Dictionary] = []
	for layer: Dictionary in composition.layers:
		authored_size = Vector2(float(layer.__cWid), float(layer.__cHei)) * float(layer.__gridSize)
		for entity: Dictionary in layer.get("entityInstances", []):
			entities.append(entity)
	var bridge_components: Array[Rect2] = _bridge_components(composition.layers as Array)
	check(bridge_components.size() == 2, "Exactly two independent authored bridge decks")
	var route: Dictionary = preload("res://scripts/dungeon/ldtk_warps.gd").resolve("res://monster_booster.ldtk", {"TargetLevel": "Room_2", "TargetWarp": "room_2_center"})
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))), "Room_2 arrival finishes")
	check((arena.get_meta("composed_levels") as PackedStringArray) == PackedStringArray(["Room_2", "Room_2_Cenario"]), "Runtime composes gameplay and scenery into a single arena")
	check(bool(route.ok) and player.position.is_equal_approx(route.spawn as Vector2), "Arrival uses the repositioned warp")
	player.contact_invulnerability = 1000.0
	check(not arena.has_node("ExplorationSpawns"), "Automatic exploration spawner is removed")
	check(arena.get_node("MapVolumes").get_child_count() == 0 and arena.get_node("ForegroundLeaves").get_child_count() == 0 and arena.get_node("Borders").get_child_count() == 0, "Temporarily hidden decoration has no sprites or physical volumes")
	var cloud_surface: Node = arena.get_node("TerrainCloudShadows")
	var ground_material: ShaderMaterial = cloud_surface.get("soil_material") as ShaderMaterial
	check(ground_material != null and float(ground_material.get_shader_parameter(&"cloud_scale")) > 96.0, "Open world enlarges the MonsterShift/Asterion cloud shapes")
	for ground: TileMapLayer in arena.get_node("LdtkLayers").get_children():
		if String(ground.name).begins_with("Floor") or String(ground.name).begins_with("Terrain"):
			var material: ShaderMaterial = ground.material as ShaderMaterial
			check(material != null and material.shader == ground_material.shader and material.get_shader_parameter(&"cloud_elapsed") == ground_material.get_shader_parameter(&"cloud_elapsed"), "Ground palettes share the same coherent cloud clock")
	check((arena.get_node("HordePedestals").get("pedestals") as Array).size() == 7, "All seven original altar instances are rendered")
	var encounters: Array = arena.get_node("SpiritHordes").get("encounters") as Array
	check(encounters.size() == 6, "Only the six external pedestals have horde events")
	var elevation: Node2D = arena.get_node("TerrainElevation") as Node2D
	var water_bounds: Rect2 = Rect2()
	for entity: Dictionary in entities:
		var point: Vector2 = Vector2(float(entity.px[0]), float(entity.px[1]))
		var size: Vector2 = Vector2(float(entity.width), float(entity.height))
		var authored_height: float = 0.0
		for field: Dictionary in entity.get("fieldInstances", []):
			if str(field.get("__identifier", "")) == "HeightPx":
				authored_height = float(field.get("__value", 0.0))
		if str(entity.__identifier) == "ElevationArea":
			check(is_equal_approx(authored_height, 56.0), "Castle height includes two extra 16 px blocks")
			check(is_equal_approx(float(elevation.call("height_at", point + size * 0.5)), authored_height), "Castle uses its authored elevated plane")
			check(is_zero_approx(float(elevation.call("height_at", Vector2(point.x + 500, point.y + size.y + 256)))), "Center uses the lower plane")
		elif str(entity.__identifier) == "ElevationRamp":
			check(is_equal_approx(float(elevation.call("height_at", point + size * 0.5)), authored_height * 0.5), "Each ramp has a gradual middle height from its authored height")
			check(not player.test_move(Transform2D(0.0, point + Vector2(size.x * 0.5, size.y + 32)), Vector2(0, -size.y - 64)), "Castle gate is physically traversable")
			check(player.test_move(Transform2D(0.0, point + Vector2(-64, size.y + 32)), Vector2(0, -size.y - 64)), "Castle ledge blocks traversal beside its gates")
		elif str(entity.__identifier) == "WaterArea":
			water_bounds = Rect2(point, size)
	for deck: Rect2 in bridge_components:
		var crossing_y: float = deck.get_center().y - 3.0
		var start: Vector2 = Vector2(deck.position.x - 16.0, crossing_y)
		check(bool(arena.call("is_ground_surface_point", start + Vector2(0, 3))), "Each bridge joins authored ground on the west bank")
		check(bool(arena.call("is_ground_surface_point", Vector2(deck.end.x + 16.0, crossing_y + 3.0))), "Each bridge joins authored ground on the east bank")
		check(not player.test_move(Transform2D(0.0, start), Vector2(deck.size.x + 32.0, 0)), "Each bridge deck allows its own full river crossing")
	if bridge_components.size() == 2:
		var between: float = (bridge_components[0].end.y + bridge_components[1].position.y) * 0.5
		check(player.test_move(Transform2D(0.0, Vector2(water_bounds.position.x - 32, between)), Vector2(water_bounds.size.x + 64, 0)), "River blocks crossing between bridges")
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	check(water.regions.size() == 1 and water.diagnostics.is_empty(), "One continuous river surface loads without diagnostics")
	await capture("center")
	for pedestal: Node2D in arena.get_node("HordePedestals").get("pedestals") as Array:
		place(pedestal.position)
		await create_timer(0.15).timeout
	for encounter: Node2D in encounters:
		check(int(encounter.get("phase")) == 0 and (encounter.get("actors") as Array).is_empty(), "Exploring and standing on pedestals cannot auto-start monsters")
	if rendered:
		for deck: Rect2 in bridge_components:
			var point: Vector2 = deck.get_center()
			place(point)
			await create_timer(0.2).timeout
			await capture("area_%d_%d" % [point.x, point.y])
		await _overview()
	print("ROOM_2_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)


func _overview() -> void:
	root.size = Vector2i(1280, 1200)
	root.content_scale_size = Vector2i(1280, 1200)
	var camera: Camera2D = Camera2D.new()
	camera.name = "OverviewCamera"
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position = authored_size * 0.5
	camera.zoom = Vector2.ONE * minf(1220.0 / authored_size.x, 1140.0 / authored_size.y)
	arena.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	(arena.get_node("RoomLighting") as CanvasLayer).hide()
	(arena.get_node("PlayerHUD") as CanvasLayer).hide()
	(arena.get_node("ArenaUI") as CanvasLayer).hide()
	await process_frame
	await capture("overview")
