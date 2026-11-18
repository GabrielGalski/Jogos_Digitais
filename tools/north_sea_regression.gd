extends SceneTree
## Three northern map rows form one sea, with an uninterrupted procedural mouth.

const OUTPUT: String = "res://output/north_sea/"
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)


func _image() -> Image:
	await physics_frame
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _pixel(image: Image, point: Vector2) -> Color:
	var scale: Vector2 = Vector2(image.get_size()) / root.get_visible_rect().size
	var screen: Vector2 = (root.get_canvas_transform() * point) * scale
	var pixel: Vector2i = Vector2i(screen.round()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	return image.get_pixelv(pixel)


func _run() -> void:
	var source_hash: String = FileAccess.get_sha256("res://monster_booster.ldtk")
	var arena: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	var deadline: int = Time.get_ticks_msec() + 3000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(arena.get("entry_complete")), "Map arrival completes")
	await physics_frame
	await physics_frame
	var player: Player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	player.get_node("GameplayKit").process_mode = Node.PROCESS_MODE_DISABLED
	player.get_node("BoosterShooter").set_process(false)
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	check(water.regions.size() == 2 and water.diagnostics.is_empty(), "One river and one sea load without diagnostics")
	var river: Node2D = null
	var sea: Node2D = null
	for region: Node2D in water.regions:
		if str(region.get_meta(&"preset", "")) == "River": river = region
		if str(region.get_meta(&"preset", "")) == "Sea": sea = region
	check(river != null and sea != null, "Both authored water presets are recognized")
	if river == null or sea == null:
		quit(1)
		return
	var sea_rect: Rect2 = sea.get_meta(&"authored_rect") as Rect2
	var river_rect: Rect2 = river.get_meta(&"authored_rect") as Rect2
	check(is_zero_approx(sea_rect.position.x) and is_equal_approx(sea_rect.size.x, 3696.0), "Sea spans the full authored map width")
	check(is_equal_approx(sea_rect.end.y, 48.0), "Exactly three 16 px rows inside the map contain sea")
	check(sea_rect.position.y <= river_rect.position.y, "Sea retains the existing out-of-map water overhang")
	for x: float in [16.0, 1200.0, 2200.0, 2752.0, 3300.0, 3680.0]:
		for y: float in [8.0, 24.0, 40.0]:
			check(not bool(arena.call("is_ground_surface_point", Vector2(x, y))), "Sea rows do not retain walkable floor at " + str(Vector2(x, y)))
	check(player.test_move(Transform2D(0.0, Vector2(1200, 128)), Vector2(0, -128)), "Raised castle shoreline blocks entry into the sea")
	check(player.test_move(Transform2D(0.0, Vector2(3300, 72)), Vector2(0, -96)), "Eastern shoreline blocks entry into the sea")
	var river_material: ShaderMaterial = (river.get_node("Surface") as Sprite2D).material as ShaderMaterial
	var sea_material: ShaderMaterial = (sea.get_node("Surface") as Sprite2D).material as ShaderMaterial
	check(river_material != sea_material, "River contour does not leak into the independent sea material")
	check(river_material.get_shader_parameter(&"river_contour_enabled") == true and sea_material.get_shader_parameter(&"river_contour_enabled") != true, "Only the river receives the narrow channel contour")
	for parameter: StringName in [&"deep_color", &"mid_color", &"highlight_color", &"cell_size_px", &"distortion_strength_px", &"flow_direction", &"flow_speed_px_s", &"pattern_seed", &"animation_speed", &"smooth_surface", &"reflection_style", &"wave_length_px", &"wave_strength", &"reflection_strength", &"calmness"]:
		check(river_material.get_shader_parameter(parameter) == sea_material.get_shader_parameter(parameter), "Water appearance and transport agree at the mouth: " + str(parameter))
	water.set_process(false)
	water.set_elapsed(19.5)
	check(river_material.get_shader_parameter(&"water_elapsed") == sea_material.get_shader_parameter(&"water_elapsed"), "Sea and river share one animation clock")
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(OUTPUT)
		arena.get_node("TerrainCloudShadows").set_process(false)
		(arena.get_node("RoomLighting") as CanvasLayer).hide()
		(arena.get_node("PlayerHUD") as CanvasLayer).hide()
		(arena.get_node("ArenaUI") as CanvasLayer).hide()
		root.size = Vector2i(960, 600)
		root.content_scale_size = root.size
		var camera: Camera2D = Camera2D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.position = Vector2(2752, 120)
		camera.zoom = Vector2.ONE * 2.0
		camera.limit_top = -16
		arena.add_child(camera)
		camera.make_current()
		camera.force_update_scroll()
		var image: Image = await _image()
		image.save_png(OUTPUT + "mouth.png")
		for x: float in [2704.5, 2752.5, 2800.5]:
			var upper: Color = _pixel(image, Vector2(x, 47.5))
			var lower: Color = _pixel(image, Vector2(x, 48.5))
			check(Vector3(upper.r - lower.r, upper.g - lower.g, upper.b - lower.b).length() < 0.04, "GPU water has no texture seam at mouth X=" + str(x))
		root.size = Vector2i(1600, 480)
		root.content_scale_size = root.size
		camera.position = Vector2(1848, 350)
		camera.zoom = Vector2.ONE * (1600.0 / 3696.0)
		camera.limit_top = 0
		camera.force_update_scroll()
		image = await _image()
		image.save_png(OUTPUT + "northern_coast.png")
	check(FileAccess.get_sha256("res://monster_booster.ldtk") == source_hash, "Runtime leaves current authoring untouched")
	print("NORTH_SEA_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
