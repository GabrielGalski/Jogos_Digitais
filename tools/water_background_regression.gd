extends SceneTree
## Headless contracts; -- --render also verifies actual water/terrain/foam pixels.

const BACKGROUND: Script = preload("res://scripts/visual/water_background.gd")
const TERRAIN: Script = preload("res://scripts/dungeon/ldtk_water_terrain.gd")
const ARENA: PackedScene = preload("res://scenes/dungeon/ldtk_arena.tscn")
const SHORE_FIELD: Script = preload("res://scripts/visual/water_shore_field.gd")
const SHORE_ADAPTER: Script = preload("res://scripts/dungeon/ldtk_water_shores.gd")
var _failures: int = 0

class TestTextures extends RefCounted:
	var image: Image

	func get_source_image(_path: String) -> Image:
		return image


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("WATER BACKGROUND FAIL: " + message)


func _land(rect: Rect2i) -> Dictionary:
	var cells: Dictionary = {}
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			cells[Vector2i(x, y)] = true
	return cells


func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	root.get_node("GameCursor").set("visible", false)
	_check_terrain()
	_check_distance_fields()
	_check_shore_semantics()
	_check_cache()
	var sea_profile: WaterProfile = load("res://resources/visual/water/sea.tres") as WaterProfile
	_expect(sea_profile.smooth_surface and sea_profile.validation_error().is_empty(), "Sea profile must be continuous and valid")
	var invalid_profile: WaterProfile = sea_profile.duplicate() as WaterProfile
	invalid_profile.reflection_strength = NAN
	_expect(not invalid_profile.validation_error().is_empty(), "non-finite surface setting accepted")
	invalid_profile = sea_profile.duplicate() as WaterProfile
	invalid_profile.foam_width_px = 24.0
	_expect(not invalid_profile.validation_error().is_empty(), "foam wider than its reach accepted")
	invalid_profile = sea_profile.duplicate() as WaterProfile
	invalid_profile.sparkle_density = NAN
	_expect(not invalid_profile.validation_error().is_empty(), "non-finite sparkle density accepted")
	invalid_profile = sea_profile.duplicate() as WaterProfile
	invalid_profile.sparkle_spacing_px = invalid_profile.sparkle_size_px * 4.0
	_expect(not invalid_profile.validation_error().is_empty(), "glint cluster can cross a procedural cell boundary")
	var water: Node2D = BACKGROUND.new() as Node2D
	root.add_child(water)
	water.call(&"configure", _land(Rect2i(20, 20, 40, 28)))
	water.set_process(false)
	var rectangles: Array[Rect2] = water.call(&"water_rectangles", Vector2i.ZERO)
	var area: float = 0.0
	for rect: Rect2 in rectangles:
		area += rect.get_area()
		_expect(not rect.intersects(Rect2(80, 80, 160, 112)), "water generated under opaque terrain")
	_expect(is_equal_approx(area, 256.0 * 256.0 - 160.0 * 112.0), "uncovered area lost")
	water.call(&"update_visible_rect", Rect2(0, 0, 255, 255))
	_expect(int(water.call(&"active_chunk_count")) == 1, "viewport chunk count")
	var chunk: Node = water.get_child(0)
	_expect(chunk.get_node_or_null("Surface") != null and chunk.get_node_or_null("Foam") != null, "water or automatic shoreline absent")
	var surface: MeshInstance2D = chunk.get_node("Surface") as MeshInstance2D
	var foam: MeshInstance2D = chunk.get_node("Foam") as MeshInstance2D
	_expect(surface.texture == foam.texture and surface.mesh == foam.mesh, "surface and foam must share their local coast field/mesh")
	water.call(&"update_visible_rect", Rect2(-100000, 100000, 256, 256))
	_expect(int(water.call(&"active_chunk_count")) <= 4, "sea allocated the whole world")
	_expect(water.get_child_count() <= 4 and not is_instance_valid(chunk.get_parent()), "offscreen chunks retained")
	water.call(&"configure", _land(Rect2i(0, 0, 64, 64)))
	water.set_process(false)
	water.call(&"update_visible_rect", Rect2(0, 0, 255, 255))
	_expect((water.call(&"water_rectangles", Vector2i.ZERO) as Array).is_empty(), "fully dry chunk contains water")
	_expect(water.get_child(0).get_child_count() == 0, "fully dry chunk loaded render meshes")
	_expect(water.z_index < -20 and not water.z_as_relative, "sea must be below every terrain layer")
	_expect(water.find_children("*", "CollisionObject2D", true, false).is_empty(), "sea created gameplay physics")
	water.call(&"set_elapsed", 3.0)
	water.set_process(true)
	paused = true
	await create_timer(0.04, true).timeout
	_expect(float(water.get("elapsed")) == 3.0, "paused sea/foam clock moved")
	paused = false
	water.free()
	await _check_arena()
	if OS.get_cmdline_user_args().has("--render"):
		await _check_rendering()
		await _check_shore_rendering()
	if _failures == 0:
		print("WATER BACKGROUND PASS: alpha/flip/offset/hidden/gaps, terrain subtraction, viewport streaming, shared distance fields/seams/corners, profile validation, pause, no physics, Room_1 without WaterAreas")
	quit(0 if _failures == 0 else 1)


func _check_terrain() -> void:
	var textures: TestTextures = TestTextures.new()
	textures.image = Image.create(32, 16, false, Image.FORMAT_RGBA8)
	textures.image.fill(Color.WHITE)
	textures.image.set_pixel(0, 0, Color.TRANSPARENT)
	textures.image.fill_rect(Rect2i(16, 0, 8, 16), Color.TRANSPARENT)
	var floor_tiles: Array = [{"px": [0, 0], "src": [0, 0], "f": 0}, {"px": [16, 0], "src": [0, 0], "f": 0}]
	var layers: Array = [
		{"__identifier": "Floor", "__tilesetDefUid": 1, "gridTiles": floor_tiles},
		{"__identifier": "PlatformUnderside", "__tilesetDefUid": 1, "__pxTotalOffsetX": -16,
			"__pxTotalOffsetY": 32, "gridTiles": [{"px": [0, 0], "src": [16, 0], "f": 1}]},
		{"__identifier": "WallsBack", "__tilesetDefUid": 2, "gridTiles": [{"px": [32, 0], "src": [8, 0]}]},
		{"__identifier": "WallsFront", "__tilesetDefUid": 2, "visible": false, "gridTiles": [{"px": [96, 0], "src": [8, 0]}]},
		{"__identifier": "ObjectsSquare", "__tilesetDefUid": 1, "gridTiles": [{"px": [128, 0], "src": [0, 0]}]},
	]
	var adapter: RefCounted = TERRAIN.new()
	var cells: Dictionary = adapter.call(&"opaque_cells", layers,
		{1: {"relPath": "test.png", "tileGridSize": 16}, 2: {"relPath": "test.png", "tileGridSize": 8}}, textures, {Vector2i.ZERO: true})
	_expect(cells.size() == 27, "opaque alpha blocks, walls, flip and excluded floor gap")
	_expect(not cells.has(Vector2i.ZERO) and cells.has(Vector2i(1, 0)), "transparent block was subtracted")
	_expect(cells.has(Vector2i(-4, 8)) and not cells.has(Vector2i(-1, 8)), "negative offset or flip lost")
	_expect(not cells.has(Vector2i(4, 0)) and not cells.has(Vector2i(24, 0)), "gap/hidden layer occluded the sea")


func _field_sample(field: Dictionary, coordinate: Vector2i, point: Vector2i) -> float:
	return _field_color(field, coordinate, point).r


func _field_color(field: Dictionary, coordinate: Vector2i, point: Vector2i) -> Color:
	if not field.has("readback"):
		field["readback"] = (field.texture as Texture2D).get_image()
	var image: Image = field.readback as Image
	if image.get_width() == 1:
		return image.get_pixel(0, 0)
	var origin: Vector2i = coordinate * 256 - Vector2i(int(field.padding), int(field.padding))
	var sample_at: Vector2i = Vector2i((Vector2(point - origin - Vector2i.ONE) / 2.0).floor())
	return image.get_pixelv(sample_at)


func _check_distance_fields() -> void:
	var builder: RefCounted = SHORE_FIELD.new()
	builder.call(&"configure", _land(Rect2i(62, 12, 4, 10)), 22.0)
	var left: Dictionary = builder.call(&"build_chunk", Vector2i.ZERO)
	var right: Dictionary = builder.call(&"build_chunk", Vector2i(1, 0))
	_expect(absf(_field_sample(left, Vector2i.ZERO, Vector2i(241, 55)) - 7.0) < 0.02, "shore distance in world pixels")
	_expect(absf(_field_sample(right, Vector2i(1, 0), Vector2i(271, 55)) - 7.0) < 0.02, "opposite shore distance")
	_expect(absf(_field_sample(left, Vector2i.ZERO, Vector2i(241, 41)) - sqrt(98.0)) < 0.02, "convex corner distance")
	_expect(_field_sample(left, Vector2i.ZERO, Vector2i(249, 55)) < 0.0, "field does not cross the shoreline")
	for y: int in range(33, 105, 2):
		for x: int in range(243, 279, 2):
			_expect(_field_sample(left, Vector2i.ZERO, Vector2i(x, y)) == _field_sample(right, Vector2i(1, 0), Vector2i(x, y)), "adjacent distance fields disagree in overlap")
	var distant: Dictionary = builder.call(&"build_chunk", Vector2i(100, -100))
	_expect(not bool(distant.has_shore) and (distant.texture as Texture2D).get_width() == 1, "open ocean loaded a full coast texture")
	var nearby: Dictionary = _land(Rect2i(0, 0, 4, 4))
	nearby.merge(_land(Rect2i(6, 0, 4, 4)))
	builder.call(&"configure", nearby, 22.0)
	var narrow: Dictionary = builder.call(&"build_chunk", Vector2i.ZERO)
	_expect(absf(_field_sample(narrow, Vector2i.ZERO, Vector2i(19, 7)) - 3.0) < 0.02, "nearby banks did not combine using minimum distance")


func _check_shore_semantics() -> void:
	var adapter: RefCounted = SHORE_ADAPTER.new()
	var common: Dictionary = {"__identifier": "WaterShoreOverride", "px": [248, 48], "__pivot": [0, 0], "width": 8, "height": 40}
	var low: Dictionary = common.duplicate(true)
	low["iid"] = "a"
	low["fieldInstances"] = [{"__identifier": "CoastType", "__value": "Beach"}, {"__identifier": "Priority", "__value": 1}]
	var high: Dictionary = common.duplicate(true)
	high["iid"] = "b"
	high["fieldInstances"] = [{"__identifier": "CoastType", "__value": "None"}, {"__identifier": "Priority", "__value": 2}]
	var disabled: Dictionary = common.duplicate(true)
	disabled["fieldInstances"] = [{"__identifier": "Enabled", "__value": false}]
	var areas: Array[Dictionary] = adapter.call(&"descriptions_from_layers", [{"entityInstances": [high, low, disabled]}])
	_expect(areas.size() == 2 and int(areas[0].priority) == 1, "shore priority/enabled normalization")
	var builder: RefCounted = SHORE_FIELD.new()
	builder.call(&"configure", _land(Rect2i(62, 12, 4, 10)), 29.0, {}, areas)
	var left: Dictionary = builder.call(&"build_chunk", Vector2i.ZERO)
	var right: Dictionary = builder.call(&"build_chunk", Vector2i(1, 0))
	var near_none: Color = _field_color(left, Vector2i.ZERO, Vector2i(241, 55))
	var other_bank: Color = _field_color(right, Vector2i(1, 0), Vector2i(271, 55))
	_expect(near_none.g == 0.0 and absf(near_none.r - 7.0) < 0.02, "None must preserve land distance and suppress foam from the other bank")
	_expect(other_bank.g == 1.0 and other_bank.a == 0.0, "override leaked through the land")
	for y: int in range(33, 105, 2):
		for x: int in range(243, 279, 2):
			_expect(_field_color(left, Vector2i.ZERO, Vector2i(x, y)) == _field_color(right, Vector2i(1, 0), Vector2i(x, y)), "semantic fields disagree across chunk seam")
	var narrow: Dictionary = _land(Rect2i(0, 0, 4, 4))
	narrow.merge(_land(Rect2i(6, 0, 4, 4)))
	var overrides: Array[Dictionary] = [{"rect": Rect2(0, 0, 16, 16), "kind": 4}, {"rect": Rect2(24, 0, 16, 16), "kind": 3}]
	builder.call(&"configure", narrow, 29.0, {}, overrides)
	var field: Dictionary = builder.call(&"build_chunk", Vector2i.ZERO)
	_expect(_field_color(field, Vector2i.ZERO, Vector2i(17, 7)).g == 0.0, "adjacent raised bank leaked foam into None side of narrow channel")
	_expect(_field_color(field, Vector2i.ZERO, Vector2i(23, 7)).a == 1.0, "raised bank lost contact-shadow classification")
	var offset: Array[Dictionary] = adapter.call(&"descriptions_from_layers", [{"__pxTotalOffsetX": -8, "entityInstances": [low]}])
	_expect((offset[0].rect as Rect2).position.x == 240.0, "shore override offset lost")
	var tie: Dictionary = low.duplicate(true)
	tie["iid"] = "z"
	var tied: Array[Dictionary] = adapter.call(&"descriptions_from_layers", [{"entityInstances": [tie, low]}])
	_expect(str(tied[1].id) == "z", "shore IID tie ordering is not deterministic")


func _check_cache() -> void:
	var water: Node2D = BACKGROUND.new() as Node2D
	root.add_child(water)
	water.set("prefetch_budget_usec", 0)
	water.set("cache_max_chunks", 2)
	water.set("cache_budget_mb", 0.5)
	water.call(&"configure", _land(Rect2i(20, 20, 40, 28)))
	water.set_process(false)
	water.call(&"update_visible_rect", Rect2(0, 0, 255, 255))
	var surface: MeshInstance2D = water.get_node("Chunk_0_0/Surface") as MeshInstance2D
	var original_texture: Texture2D = surface.texture
	water.call(&"update_visible_rect", Rect2(256, 0, 255, 255))
	water.call(&"update_visible_rect", Rect2(0, 0, 255, 255))
	_expect((water.get_node("Chunk_0_0/Surface") as MeshInstance2D).texture == original_texture, "return visit rebuilt field instead of cache hit")
	_expect(int((water.call(&"diagnostics") as Dictionary).cache_hits) == 1, "cache hit diagnostic incorrect")
	var profile: WaterProfile = (water.get("profile") as WaterProfile).duplicate() as WaterProfile
	profile.deep_color = Color("173444")
	water.set("profile", profile)
	water.call(&"apply_profile")
	_expect((water.get_node("Chunk_0_0/Surface") as MeshInstance2D).texture == original_texture, "color edit invalidated coast geometry")
	profile.shallow_width_px = 24.0
	water.call(&"apply_profile")
	_expect(water.get_child_count() == 0 and int((water.call(&"diagnostics") as Dictionary).cache_chunks) == 0, "reach edit failed to invalidate active/cached fields")
	for x: int in range(8):
		water.call(&"update_visible_rect", Rect2(x * 256, 0, 255, 255))
	var diagnostic: Dictionary = water.call(&"diagnostics")
	_expect(int(diagnostic.cache_chunks) <= 2 and int(diagnostic.cache_bytes) <= 524288, "cache exceeded count or byte budget")
	water.set("prefetch_budget_usec", 1500)
	var builds: int = int(diagnostic.builds)
	water.call(&"_prepare_nearby")
	_expect(int((water.call(&"diagnostics") as Dictionary).builds) <= builds + 1, "prefetch built multiple synchronous chunks in one budget")
	water.set("cache_max_chunks", 0)
	water.call(&"update_visible_rect", Rect2(8192, -8192, 255, 255))
	_expect(int((water.call(&"diagnostics") as Dictionary).cache_chunks) == 0, "disabled cache retained retired resources")
	water.free()


func _check_arena() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	for level: Dictionary in data.levels:
		for layer: Dictionary in level.layerInstances:
			if str(layer.__type) == "Entities":
				var remaining: Array = []
				for entity: Dictionary in layer.entityInstances:
					if str(entity.__identifier) != "WaterArea":
						remaining.append(entity)
				layer.entityInstances = remaining
	var fixture: FileAccess = FileAccess.open("res://tmp/automatic_water_fixture.ldtk", FileAccess.WRITE)
	fixture.store_string(JSON.stringify(data))
	fixture.close()
	var arena: Node2D = ARENA.instantiate() as Node2D
	arena.set("map_path", "res://tmp/automatic_water_fixture.ldtk")
	var started_us: int = Time.get_ticks_usec()
	root.add_child(arena)
	print("WATER BACKGROUND Room_1 initial build: %.1f ms" % ((Time.get_ticks_usec() - started_us) / 1000.0))
	await create_timer(0.1).timeout
	var water: Node2D = arena.get_node("Water") as Node2D
	_expect(str(arena.get("level_name")) == "Room_1", "arena did not start in Room_1")
	_expect(water.get_script() == BACKGROUND and int(water.call(&"active_chunk_count")) > 0, "sea required WaterArea")
	_expect(arena.get_node_or_null("Nox") != null, "player missing")
	if OS.get_cmdline_user_args().has("--render"):
		await create_timer(0.5).timeout
		arena.get_node("ArenaUI").set("visible", false)
		water.set_process(false)
		water.call(&"set_elapsed", 4.0)
		var capture: Image = await _capture()
		capture.save_png("res://tmp/water_room1_960.png")
		root.size = Vector2i(480, 270)
		var small: Image = await _capture()
		small.save_png("res://tmp/water_room1_480.png")
		root.size = Vector2i(960, 540)
		root.size = Vector2i(1920, 1080)
		var large: Image = await _capture()
		large.save_png("res://tmp/water_room1_1920.png")
		root.size = Vector2i(960, 540)
		if OS.get_cmdline_user_args().has("--sequence"):
			DirAccess.make_dir_recursive_absolute("res://tmp/water_quality_frames")
			for frame: int in range(48):
				water.call(&"set_elapsed", 4.0 + frame * 0.125)
				var animation_frame: Image = await _capture()
				animation_frame.save_png("res://tmp/water_quality_frames/frame_%03d.png" % frame)
			DirAccess.make_dir_recursive_absolute("res://tmp/water_motion_frames")
			var original_camera: Camera2D = arena.get("_camera") as Camera2D
			var center: Vector2 = original_camera.global_position
			var camera: Camera2D = Camera2D.new()
			camera.zoom = original_camera.zoom
			camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
			camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			root.add_child(camera)
			camera.make_current()
			var builds: int = int((water.call(&"diagnostics") as Dictionary).builds)
			for frame: int in range(48):
				var progress: float = sin(frame / 47.0 * PI)
				camera.global_position = center + Vector2(progress * 800.0, progress * 160.0)
				camera.reset_physics_interpolation()
				camera.force_update_scroll()
				water.call(&"_prepare_nearby")
				water.call(&"set_elapsed", 4.0 + frame * 0.125)
				var motion_frame: Image = await _capture()
				motion_frame.save_png("res://tmp/water_motion_frames/frame_%03d.png" % frame)
				var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color") as Color
				for sample_at: Vector2i in [Vector2i(4, 4), Vector2i(955, 4), Vector2i(955, 535), Vector2i(4, 535)]:
					_expect(not motion_frame.get_pixelv(sample_at).is_equal_approx(clear), "camera motion exposed a missing water region")
				if frame > 24:
					_expect(int((water.call(&"diagnostics") as Dictionary).builds) == builds, "returning camera rebuilt cached chunks")
				else:
					builds = int((water.call(&"diagnostics") as Dictionary).builds)
			camera.free()
	arena.free()


func _capture() -> Image:
	await physics_frame
	await physics_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _check_rendering() -> void:
	var water: Node2D = BACKGROUND.new() as Node2D
	# Exercise optional effects independently of the shipped artistic preset.
	var effects_profile: WaterProfile = (water.get("profile") as WaterProfile).duplicate() as WaterProfile
	effects_profile.sparkle_intensity = 1.0
	effects_profile.foam_opacity = 0.75
	water.set("profile", effects_profile)
	root.add_child(water)
	var solid: Dictionary = _land(Rect2i(20, 18, 60, 30))
	var hole: Dictionary = _land(Rect2i(36, 28, 12, 10))
	for cell: Vector2i in hole:
		solid.erase(cell)
	water.call(&"configure", solid)
	water.set_process(false)
	water.call(&"set_elapsed", 2.0)
	var terrain: Node2D = Node2D.new()
	terrain.z_index = -20
	root.add_child(terrain)
	# Draw the exact opaque cells used by the adapter, including an inner pond.
	for cell: Vector2i in solid:
		var polygon: Polygon2D = Polygon2D.new()
		var at: Vector2 = Vector2(cell * 4)
		polygon.polygon = PackedVector2Array([at, at + Vector2(4, 0), at + Vector2(4, 4), at + Vector2(0, 4)])
		polygon.color = Color("45283c")
		terrain.add_child(polygon)
	var image: Image = await _capture()
	image.save_png("res://tmp/automatic_water_foam_960.png")
	_expect(image.get_pixel(200, 160).is_equal_approx(Color("45283c")), "water or foam covered dry terrain")
	var original_profile: WaterProfile = water.get("profile") as WaterProfile
	var body_profile: WaterProfile = original_profile.duplicate() as WaterProfile
	body_profile.sparkle_intensity = 0.0
	water.set("profile", body_profile)
	water.call(&"apply_profile")
	var body_image: Image = await _capture()
	water.set("profile", original_profile)
	water.call(&"apply_profile")
	var colors: Dictionary = {}
	var maximum_step: float = 0.0
	var bright_pixels: int = 0
	var strongest_glint: float = 0.0
	for y: int in range(16, 520):
		for x: int in range(720, 950):
			var color: Color = body_image.get_pixel(x, y)
			colors[color.to_rgba32()] = true
			var adjacent: Color = body_image.get_pixel(x - 1, y)
			maximum_step = maxf(maximum_step, maxf(absf(color.r - adjacent.r), maxf(absf(color.g - adjacent.g), absf(color.b - adjacent.b))))
			var glint: float = image.get_pixel(x, y).r - color.r
			strongest_glint = maxf(strongest_glint, glint)
			if glint > 0.15:
				bright_pixels += 1
	_expect(colors.size() > 64 and maximum_step < 0.08, "continuous water body regressed to hard palette/cell edges")
	_expect(strongest_glint > 0.3 and bright_pixels > 0 and bright_pixels < 504 * 230 * 0.04, "sun glints must be bright and sparse")
	water.set("foam_enabled", false)
	water.call(&"apply_profile")
	var without: Image = await _capture()
	_expect(image.get_data() != without.get_data(), "automatic foam had no visible pixels")
	water.set("foam_enabled", true)
	water.call(&"apply_profile")
	water.call(&"set_elapsed", 5.0)
	var later: Image = await _capture()
	_expect(later.get_data() != image.get_data(), "water and shoreline stayed static")
	var still_profile: WaterProfile = (water.get("profile") as WaterProfile).duplicate() as WaterProfile
	still_profile.animation_speed = 0.0
	water.set("profile", still_profile)
	water.call(&"configure", solid)
	water.set_process(false)
	var frozen: Image = await _capture()
	water.call(&"set_elapsed", 100.0)
	var still: Image = await _capture()
	_expect(frozen.get_data() == still.get_data(), "animation_speed=0 did not freeze surface and foam together")
	var camera: Camera2D = Camera2D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(240, 135)
	root.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var before: Image = await _capture()
	camera.position.x += 32.0
	camera.reset_physics_interpolation()
	camera.force_update_scroll()
	water.call(&"refresh_view")
	var moved: Image = await _capture()
	_expect(before.get_region(Rect2i(64, 0, 896, 540)).get_data() == moved.get_region(Rect2i(0, 0, 896, 540)).get_data(), "sea or foam followed the camera / chunk seam")
	camera.position = Vector2(8192, -8192)
	camera.zoom = Vector2(0.6, 0.6)
	camera.rotation = 0.18
	camera.reset_physics_interpolation()
	camera.force_update_scroll()
	root.size = Vector2i(1280, 720)
	var distant: Image = await _capture()
	var clear_color: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color") as Color
	for sample_at: Vector2i in [Vector2i(4, 4), Vector2i(1275, 4), Vector2i(1275, 715), Vector2i(4, 715)]:
		_expect(not distant.get_pixelv(sample_at).is_equal_approx(clear_color), "teleport/zoom/rotation/resize left a dry viewport corner")
	_expect(int(water.call(&"active_chunk_count")) < 32, "distant camera retained old world chunks")
	distant.save_png("res://tmp/water_streaming_rotated_1280.png")
	camera.free()
	terrain.free()
	water.free()
	print("WATER BACKGROUND RENDER: terrain hides water/foam, outer/inner banks, animation, world anchoring, chunk seams, teleport/zoom/rotation/resize, 960/1280 previews")


func _image_error(a: Image, b: Image, region: Rect2i) -> float:
	var error: float = 0.0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var ac: Color = a.get_pixel(x, y)
			var bc: Color = b.get_pixel(x, y)
			error = maxf(error, maxf(absf(ac.r - bc.r), maxf(absf(ac.g - bc.g), absf(ac.b - bc.b))))
	return error


func _check_shore_rendering() -> void:
	root.size = Vector2i(960, 540)
	var solid: Dictionary = {}
	var styles: Dictionary = {}
	var terrain: Node2D = Node2D.new()
	terrain.z_index = -20
	root.add_child(terrain)
	var names: Array[String] = ["Default", "Rock", "Beach", "Raised", "None"]
	for kind: int in range(5):
		var cells: Dictionary = _land(Rect2i(5 + kind * 22, 20, 12, 16))
		solid.merge(cells)
		for cell: Vector2i in cells:
			styles[cell] = kind
		var rect: Rect2 = Rect2(20 + kind * 88, 80, 48, 64)
		var polygon: Polygon2D = Polygon2D.new()
		polygon.polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])
		polygon.color = Color("45283c")
		terrain.add_child(polygon)
		var label: Label = Label.new()
		label.text = names[kind]
		label.position = Vector2(rect.position.x, 50)
		label.add_theme_font_override("font", load("res://assets/font/determination.ttf") as Font)
		label.add_theme_font_size_override("font_size", 10)
		terrain.add_child(label)
	var water: Node2D = BACKGROUND.new() as Node2D
	var effects_profile: WaterProfile = (water.get("profile") as WaterProfile).duplicate() as WaterProfile
	effects_profile.foam_opacity = 0.75
	water.set("profile", effects_profile)
	root.add_child(water)
	water.call(&"configure", solid, styles)
	water.set_process(false)
	water.call(&"set_elapsed", 4.0)
	var combined: Image = await _capture()
	DirAccess.make_dir_recursive_absolute("res://output/water/evolution/after")
	combined.save_png("res://output/water/evolution/after/coast_types_960.png")
	water.set("combine_foam", false)
	water.call(&"apply_profile")
	var separate: Image = await _capture()
	separate.save_png("res://tmp/water_coast_separate.png")
	var composite_error: float = _image_error(combined, separate, Rect2i(0, 0, 960, 540))
	_expect(composite_error <= 1.01 / 255.0, "combined and separate foam changed appearance: %.6f" % composite_error)
	water.set("foam_enabled", false)
	water.call(&"apply_profile")
	var without: Image = await _capture()
	_expect(_image_error(combined, without, Rect2i(720, 140, 140, 168)) == 0.0, "None bank received foam in actual rendered pixels")
	_expect(_image_error(combined, without, Rect2i(20, 140, 140, 168)) > 0.01, "default bank produced no visible foam")
	var profile: WaterProfile = (water.get("profile") as WaterProfile).duplicate() as WaterProfile
	profile.shore_shadow_strength = 0.0
	water.set("profile", profile)
	water.call(&"apply_profile")
	var no_shadow: Image = await _capture()
	_expect(_image_error(without, no_shadow, Rect2i(540, 145, 130, 160)) > 0.005, "Raised bank casts no contact shadow")
	_expect(_image_error(without, no_shadow, Rect2i(360, 145, 130, 160)) == 0.0, "Beach bank acquired an elevated contact shadow")
	water.free()
	terrain.free()
	print("WATER COAST RENDER: five styles, nearest None prevents leakage, Raised-only shadow, combined/separate foam within 1/255")
