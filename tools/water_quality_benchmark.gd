extends SceneTree
## Reproducible CPU/resource benchmark. -- --render measures an isolated viewport too.

const BACKGROUND: Script = preload("res://scripts/visual/water_background.gd")
const TERRAIN: Script = preload("res://scripts/dungeon/ldtk_water_terrain.gd")
const FIELD: Script = preload("res://scripts/visual/water_shore_field.gd")
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
var _report: Dictionary = {}
var _tag: String = "before"
var _background_script: Script = BACKGROUND
var _field_script: Script = FIELD
var _baseline: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _stats(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"median_ms": samples[floori(samples.size() * 0.5)], "p95_ms": samples[mini(samples.size() - 1, floori(samples.size() * 0.95))], "samples": samples.size()}


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--tag"):
		_tag = args[args.find("--tag") + 1]
	_baseline = args.has("--baseline-dir")
	if _baseline:
		var directory: String = args[args.find("--baseline-dir") + 1].trim_suffix("/")
		_background_script = load(directory + "/water_background.gd") as Script
		_field_script = load(directory + "/water_shore_field.gd") as Script
	_report = {"tag": _tag, "engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"method": "Godot debug build; warmup excluded; CPU wall time via Time.get_ticks_usec; resource upload included; no FPS inference"}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var layers: Array = []
	for level: Dictionary in data.levels:
		if str(level.identifier) == "Room_1":
			layers = level.layerInstances
	var definitions: Dictionary = {}
	for definition: Dictionary in data.defs.tilesets:
		definitions[int(definition.uid)] = definition
	var floor_cells: Dictionary = {}
	for layer: Dictionary in layers:
		if str(layer.__identifier) == "Floor":
			for tile: Dictionary in layer.gridTiles:
				floor_cells[Vector2i(floori(float(tile.px[0]) / 16.0), floori(float(tile.px[1]) / 16.0))] = true
	var textures: RefCounted = TEXTURES.new()
	var adapter: RefCounted = TERRAIN.new()
	var preparation: Array[float] = []
	var solid: Dictionary = {}
	for sample: int in range(6):
		var begin: int = Time.get_ticks_usec()
		solid = adapter.call(&"opaque_cells", layers, definitions, textures, floor_cells)
		if sample > 0:
			preparation.append((Time.get_ticks_usec() - begin) / 1000.0)
	_report["terrain_prepare"] = _stats(preparation)
	_report["opaque_cells"] = solid.size()
	var coast_chunks: Dictionary = {}
	for cell: Vector2i in solid:
		if not solid.has(cell + Vector2i.RIGHT) or not solid.has(cell + Vector2i.DOWN) or not solid.has(cell + Vector2i.LEFT) or not solid.has(cell + Vector2i.UP):
			coast_chunks[Vector2i((Vector2(cell * 4) / 256.0).floor())] = true
	var coordinates: Array = coast_chunks.keys()
	coordinates.sort()
	_report["coastal_chunks"] = coordinates.size()
	var field_builder: RefCounted = _field_script.new()
	var sea: WaterProfile = load("res://resources/visual/water/sea.tres") as WaterProfile
	var field_reach: float = 22.0 if _baseline else maxf(sea.shallow_width_px * 1.35, sea.foam_reach_px) + 2.0
	_report["field_reach_world_px"] = field_reach
	field_builder.call(&"configure", solid, field_reach)
	var field_times: Array[float] = []
	var field_bytes: int = 0
	for repeat: int in range(4):
		for coordinate: Vector2i in coordinates:
			var begin: int = Time.get_ticks_usec()
			var field: Dictionary = field_builder.call(&"build_chunk", coordinate)
			if repeat > 0:
				field_times.append((Time.get_ticks_usec() - begin) / 1000.0)
			if repeat == 1:
				field_bytes += (field.texture as Texture2D).get_image().get_data_size()
	_report["field_build"] = _stats(field_times)
	_report["all_coastal_texture_bytes"] = field_bytes
	var complex_cells: Dictionary = {}
	for y: int in range(6, 58):
		for x: int in range(6, 58):
			if x < 22 + floori(sin(y * 0.37) * 7.0) or x > 42 + floori(cos(y * 0.43) * 6.0):
				complex_cells[Vector2i(x, y)] = true
	field_builder.call(&"configure", complex_cells, field_reach)
	var complex_times: Array[float] = []
	for sample: int in range(8):
		var begin: int = Time.get_ticks_usec()
		field_builder.call(&"build_chunk", Vector2i.ZERO)
		if sample > 0:
			complex_times.append((Time.get_ticks_usec() - begin) / 1000.0)
	_report["complex_field_build"] = _stats(complex_times)
	var water: Node2D = _background_script.new() as Node2D
	root.add_child(water)
	var configure_times: Array[float] = []
	for sample: int in range(6):
		var begin: int = Time.get_ticks_usec()
		water.call(&"configure", solid)
		water.set_process(false)
		if sample > 0:
			configure_times.append((Time.get_ticks_usec() - begin) / 1000.0)
	_report["water_configure"] = _stats(configure_times)
	var initial: Array[float] = []
	var returning: Array[float] = []
	var triangle_count: int = 0
	for repeat: int in range(2):
		for coordinate: Vector2i in coordinates:
			var begin: int = Time.get_ticks_usec()
			water.call(&"update_visible_rect", Rect2(Vector2(coordinate * 256), Vector2(255, 255)))
			var duration: float = (Time.get_ticks_usec() - begin) / 1000.0
			if repeat == 0:
				initial.append(duration)
				for mesh_node: Node in water.find_children("Surface", "MeshInstance2D", true, false):
					var mesh: Mesh = (mesh_node as MeshInstance2D).mesh
					triangle_count += mesh.surface_get_array_len(0) / 3
			else:
				returning.append(duration)
	_report["first_visit_chunk"] = _stats(initial)
	_report["return_visit_chunk"] = _stats(returning)
	_report["coastal_triangles_surface"] = triangle_count
	if water.has_method(&"diagnostics"):
		_report["streaming"] = water.call(&"diagnostics")
	water.free()
	if args.has("--render"):
		await _render_comparison(solid)
	DirAccess.make_dir_recursive_absolute("res://output/water/evolution")
	var file: FileAccess = FileAccess.open("res://output/water/evolution/benchmark_%s.json" % _tag, FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	print("WATER BENCHMARK " + JSON.stringify(_report))
	quit()


func _render_comparison(solid: Dictionary) -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	root.get_node("GameCursor").set("visible", false)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var water: Node2D = _background_script.new() as Node2D
	viewport.add_child(water)
	water.call(&"configure", solid)
	water.set_process(false)
	water.call(&"set_elapsed", 4.0)
	var camera: Camera2D = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position = Vector2(768, 768)
	viewport.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var modes: Array[Dictionary] = [
		{"id": "surface_foam_voronoi", "foam": true, "voronoi": 0.035},
		{"id": "surface_foam_no_voronoi", "foam": true, "voronoi": 0.0},
		{"id": "surface_foam_coastal", "foam": true, "voronoi": 0.0},
		{"id": "surface_foam_combined", "foam": true, "voronoi": 0.0},
		{"id": "surface_only", "foam": false, "voronoi": 0.0},
		{"id": "empty", "foam": false, "voronoi": 0.0},
	]
	var rendering: Dictionary = {}
	for mode: Dictionary in modes:
		if _baseline and str(mode.id) in ["surface_foam_coastal", "surface_foam_combined"]:
			continue
		var profile: WaterProfile = (water.get("profile") as WaterProfile).duplicate() as WaterProfile
		profile.voronoi_strength = float(mode.voronoi)
		water.set("profile", profile)
		water.set("foam_enabled", bool(mode.foam))
		if not _baseline:
			water.set("combine_foam", str(mode.id) == "surface_foam_combined")
		water.call(&"configure", solid)
		water.set_process(false)
		water.visible = str(mode.id) != "empty"
		water.call(&"refresh_view")
		var coast_mesh_usec: int = 0
		if str(mode.id) == "surface_foam_coastal":
			var mesh_begin: int = Time.get_ticks_usec()
			for node: Node in water.find_children("Foam", "MeshInstance2D", true, false):
				_restrict_foam_mesh(node as MeshInstance2D, solid)
			coast_mesh_usec = Time.get_ticks_usec() - mesh_begin
		var warm_started: int = Time.get_ticks_usec()
		while Time.get_ticks_usec() - warm_started < 1000000:
			await RenderingServer.frame_post_draw
		var gpu: Array[float] = []
		var cpu: Array[float] = []
		var wall: Array[float] = []
		var previous: int = Time.get_ticks_usec()
		for frame: int in range(240):
			await RenderingServer.frame_post_draw
			var now: int = Time.get_ticks_usec()
			wall.append((now - previous) / 1000.0)
			previous = now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()))
		var triangles: int = 0
		for node: Node in water.find_children("*", "MeshInstance2D", true, false):
			var mesh_node: MeshInstance2D = node as MeshInstance2D
			if mesh_node.is_visible_in_tree():
				triangles += floori(mesh_node.mesh.surface_get_array_len(0) / 3.0)
		rendering[str(mode.id)] = {"viewport_gpu": _stats(gpu), "viewport_cpu": _stats(cpu), "frame_wall": _stats(wall),
			"triangles": triangles, "coastal_mesh_prepare_ms": coast_mesh_usec / 1000.0}
		if str(mode.id).begins_with("surface_foam"):
			viewport.get_texture().get_image().save_png("res://output/water/evolution/%s_%s.png" % [_tag, mode.id])
	_report["isolated_render_1920x1080"] = rendering
	_report["gpu_time_available"] = float(rendering.surface_foam_voronoi.viewport_gpu.median_ms) > 0.0
	viewport.free()


func _restrict_foam_mesh(foam: MeshInstance2D, solid: Dictionary) -> void:
	# Conservative 4px cells; +6px includes all fragments influenced by the field.
	# Prototype only. Readback cost is reported and not hidden in production timing.
	var image: Image = foam.texture.get_image()
	var verts: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var coordinate: Vector2i = Vector2i((foam.get_parent() as Node2D).position / 256.0)
	var profile: WaterProfile = (foam.get_parent().get_parent() as Node2D).get("profile") as WaterProfile
	var padding: float = (image.get_width() * 2 - 256) * 0.5
	for y: int in range(0, 256, 4):
		for x: int in range(0, 256, 4):
			if solid.has(coordinate * 64 + Vector2i(floori(x / 4.0), floori(y / 4.0))):
				continue
			var point: Vector2 = Vector2(x + 2, y + 2)
			var uv: Vector2 = (point + Vector2.ONE * padding) / (256.0 + padding * 2.0)
			var sample_at: Vector2i = Vector2i(uv * Vector2(image.get_size()))
			if image.get_pixelv(sample_at).r > profile.foam_reach_px + 6.0:
				continue
			for offset: Vector2 in [Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 0), Vector2(4, 4), Vector2(0, 4)]:
				var vertex: Vector2 = Vector2(x, y) + offset
				verts.append(vertex)
				uvs.append((vertex + Vector2.ONE * padding) / (256.0 + padding * 2.0))
	if verts.is_empty():
		foam.visible = false
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	foam.mesh = mesh
