extends "res://tools/river_contour_regression.gd"
## Actual curved bank, protected cliff, bridge physics and before/after GPU pixels.

const BANK_OUTPUT: String = "res://output/river_bank/"
var _source_hash: String = ""
var _water_material: ShaderMaterial = null


func _initialize() -> void:
	_source_hash = FileAccess.get_sha256(MAP_FILE)
	super._initialize()


func _check_preservation() -> void:
	# This task changes presentation only; compare against the current authored
	# file rather than a historical migration that predates subsequent painting.
	check(FileAccess.get_sha256(MAP_FILE) == _source_hash, "All current LDtk authoring stays byte-for-byte unchanged")
	report["ldtk_sha256"] = _source_hash


func _physics_checks() -> void:
	await super._physics_checks()
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	_water_material = (water.regions[0].get_node("Surface") as Sprite2D).material as ShaderMaterial
	var profile: WaterProfile = load("res://resources/visual/water/open_world_river.tres") as WaterProfile
	check(profile.validation_error().is_empty(), "River bank profile validates")
	check(bool(_water_material.get_shader_parameter("bank_enabled")), "The open-world river enables its earthen bank")
	check(is_equal_approx(float(_water_material.get_shader_parameter("bank_width_px")), 4.0), "Face uses four world pixels")
	check(is_equal_approx(float(_water_material.get_shader_parameter("bank_submerged_width_px")), 8.0), "Submerged shelf extends eight world pixels")
	check(is_equal_approx(float(_water_material.get_shader_parameter("bank_contact_width_px")), 1.5), "Water contact remains narrow")
	check(is_equal_approx(float(_water_material.get_shader_parameter("river_west_bank_start_y")), 1088.0), "The visual west border meets the actual cliff foot")
	check(not (load("res://resources/visual/water/lake.tres") as WaterProfile).bank_enabled
		and not (load("res://resources/visual/water/sea.tres") as WaterProfile).bank_enabled, "Other water profiles retain their own presentation")
	var model: RefCounted = arena.get_node("RiverContour").get("contour") as RefCounted
	var upper: Vector4 = model.call("banks_at", 800.0) as Vector4
	var lower: Vector4 = model.call("banks_at", float(model.get("locked_west_y")) + 96.0) as Vector4
	var ending: Vector4 = model.call("banks_at", (model.get("valid_y") as Vector2).y - 4.0) as Vector4
	check(is_zero_approx(upper.z) and upper.w > 0.99, "Upper cliff excludes the left face while the right bank continues")
	check(lower.z > 0.99 and lower.w > 0.99 and ending.w > 0.99, "Both low banks and the final east bank remain enabled")
	report["face_px"] = profile.bank_width_px
	report["submerged_px"] = profile.bank_submerged_width_px
	report["contact_px"] = profile.bank_contact_width_px
	report["face_color"] = profile.bank_color.to_html()


func _pixel(image: Image, point: Vector2) -> Color:
	var stretch: Vector2 = Vector2(image.get_size()) / root.get_visible_rect().size
	var screen: Vector2 = (root.get_canvas_transform() * point) * stretch
	var pixel: Vector2i = Vector2i(screen.round()).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
	return image.get_pixelv(pixel)


func _difference(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _image() -> Image:
	# Flush uniform/camera changes before reading the rendered framebuffer.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _save_bank_view(label: String) -> void:
	var image: Image = await _image()
	check(image.save_png(BANK_OUTPUT + label + ".png") == OK, "Save bank view " + label)


func _render_views() -> void:
	if not rendered: return
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	water.set_process(false)
	water.set_elapsed(12.0)
	arena.get_node("TerrainCloudShadows").set_process(false)
	var lighting: CanvasLayer = arena.get_node("RoomLighting") as CanvasLayer
	lighting.set_process(false)
	var light_material: ShaderMaterial = lighting.get("_material") as ShaderMaterial
	light_material.set_shader_parameter("ambient_multiplier", Color.WHITE)
	light_material.set_shader_parameter("center_multiplier", Color.WHITE)
	light_material.set_shader_parameter("saturation", 1.0)
	var model: RefCounted = arena.get_node("RiverContour").get("contour") as RefCounted
	var banks: Vector4 = model.call("banks_at", 1808.0) as Vector4
	_place(Vector2(banks.x - 24.0, 1808))
	await _frame(Vector2((banks.x + banks.y) * 0.5, 1808), 2.0)
	_water_material.set_shader_parameter("bank_enabled", false)
	var before: Image = await _image()
	before.save_png(BANK_OUTPUT + "01_without_bank.png")
	_water_material.set_shader_parameter("bank_enabled", true)
	var after: Image = await _image()
	after.save_png(BANK_OUTPUT + "02_bank_palette.png")
	var face_color: Color = Color("#3d2436")
	var pixel_report: Array[Dictionary] = []
	for side: int in range(2):
		var direction: float = 1.0 if side == 0 else -1.0
		var coast_x: float = banks.x if side == 0 else banks.y
		var face_point: Vector2 = Vector2(coast_x + direction * 2.0, 1808)
		var foot_point: Vector2 = Vector2(coast_x + direction * 7.0, 1808)
		var deep_point: Vector2 = Vector2(coast_x + direction * 32.0, 1808)
		var face: Color = _pixel(after, face_point)
		check(_difference(face, face_color) < 0.06, "GPU draws the solid four-pixel face on side " + str(side))
		check(_difference(face, _pixel(before, face_point)) > 0.05, "Face separates water from land on side " + str(side))
		check(_difference(_pixel(after, foot_point), face_color) > 0.06, "The submerged foot returns to water colors on side " + str(side))
		check(_difference(_pixel(after, deep_point), _pixel(before, deep_point)) < 0.015, "Deep water stays outside the border treatment on side " + str(side))
		check(face.a > 0.99 and _pixel(after, foot_point).a > 0.99, "Border and shallow shelf remain opaque on side " + str(side))
		pixel_report.append({"side": side, "face_rgb": face.to_html(), "deep_change": _difference(_pixel(after, deep_point), _pixel(before, deep_point))})
	var upper: Vector4 = model.call("banks_at", 800.0) as Vector4
	await _frame(Vector2((upper.x + upper.y) * 0.5, 800), 2.0)
	_water_material.set_shader_parameter("bank_enabled", false)
	before = await _image()
	_water_material.set_shader_parameter("bank_enabled", true)
	after = await _image()
	check(_difference(_pixel(before, Vector2(upper.x + 3.0, 800)), _pixel(after, Vector2(upper.x + 3.0, 800))) < 0.01, "GPU leaves the protected west cliff unchanged")
	check(_difference(_pixel(after, Vector2(upper.y - 2.0, 800)), face_color) < 0.06, "GPU keeps the east border beside the upper map")
	var junction: Vector4 = model.call("banks_at", 1104.0) as Vector4
	await _frame(Vector2((junction.x + junction.y) * 0.5, 1104), 2.0)
	after = await _image()
	check(_difference(_pixel(after, Vector2(junction.x + 2.0, 1104)), face_color) < 0.06, "The visual border fills the straight shore below the cliff without a 32 px gap")
	report["pixels"] = pixel_report
	report["water_elapsed"] = _water_material.get_shader_parameter("water_elapsed")
	report["water_modulate"] = water.modulate.to_html()
	lighting.call("apply_profile")
	var views: Array[Dictionary] = [
		{"id": "03_cliff_transition", "y": 1120.0, "zoom": 1.7},
		{"id": "04_upper_bridge", "y": 1440.0, "zoom": 1.7},
		{"id": "05_both_banks", "y": 1808.0, "zoom": 2.0},
		{"id": "06_lower_bridge", "y": 2280.0, "zoom": 1.7},
		{"id": "07_lower_curve", "y": 2720.0, "zoom": 1.7},
		{"id": "08_east_end", "y": 3176.0, "zoom": 1.7},
	]
	for view: Dictionary in views:
		var pair: Vector4 = model.call("banks_at", float(view.y)) as Vector4
		_place(Vector2(pair.x - 24.0, float(view.y)))
		await _frame(Vector2((pair.x + pair.y) * 0.5, float(view.y)), float(view.zoom))
		await _save_bank_view(str(view.id))
	root.content_scale_size = Vector2i(480, 320)
	root.size = Vector2i(1440, 960)
	_place(Vector2(banks.x - 24.0, 1808))
	await _frame(Vector2((banks.x + banks.y) * 0.5, 1808), 1.0)
	await _save_bank_view("09_native_scale")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(BANK_OUTPUT)
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
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	# Keep this visual/shore test independent of ambient encounter simulation.
	var ambient: Node2D = arena.get_node_or_null("FlyingEyeZones") as Node2D
	if ambient != null:
		ambient.process_mode = Node.PROCESS_MODE_DISABLED
		ambient.hide()
	for overlay_name: String in ["PlayerHUD", "ArenaUI"]:
		var overlay: CanvasLayer = arena.get_node_or_null(overlay_name) as CanvasLayer
		if overlay != null: overlay.hide()
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arena.add_child(camera)
	camera.make_current()
	# Disabling the arrival beam still runs the scene's 0.45 s black fade.
	# Pixel comparisons must begin only after that overlay has been removed.
	for attempt: int in range(120):
		if bool(arena.get("entry_complete")): break
		await process_frame
	check(bool(arena.get("entry_complete")), "Arrival fade finishes before visual measurements")
	await _settle()
	await _physics_checks()
	await _render_views()
	_check_preservation()
	report["rendered"] = rendered
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var stream: FileAccess = FileAccess.open(BANK_OUTPUT + ("render_report.json" if rendered else "physics_report.json"), FileAccess.WRITE)
	stream.store_string(JSON.stringify(report, "\t") + "\n")
	stream.close()
	print("RIVER_BANK_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
