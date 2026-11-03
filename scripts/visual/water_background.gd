extends Node2D
## Visual sea: visible geometry and a bounded retired/prefetched resource cache.

const WATER_SHADER: Shader = preload("res://shaders/water_voronoi.gdshader")
const FOAM_SHADER: Shader = preload("res://shaders/water_shore_foam.gdshader")
const DEFAULT_PROFILE: WaterProfile = preload("res://resources/visual/water/sea.tres")
const SHORE_FIELD: Script = preload("res://scripts/visual/water_shore_field.gd")
const CHUNK_SIZE: int = 256
const CELL_SIZE: int = 4
const CELLS_PER_CHUNK: int = 64

@export var profile: WaterProfile = DEFAULT_PROFILE
@export var foam_enabled: bool = true
## Alternate pass retained for renderer comparisons; default chosen by benchmark.
@export var combine_foam: bool = true
@export_group("Streaming")
@export_range(0, 128) var cache_max_chunks: int = 48
@export_range(0.0, 64.0) var cache_budget_mb: float = 12.0
@export_range(0, 2) var prefetch_margin_chunks: int = 1
## Soft budget: a started chunk finishes synchronously; teleports stay complete.
@export_range(0, 10000) var prefetch_budget_usec: int = 1500
var elapsed: float = 0.0
var _solid_cells: Dictionary = {}
var _shore_styles: Dictionary = {}
var _shore_overrides: Array[Dictionary] = []
var _occupancy: Dictionary = {}
var _chunks: Dictionary[Vector2i, Node2D] = {}
var _cache: Dictionary[Vector2i, Node2D] = {}
var _lru: Array[Vector2i] = []
var _cache_bytes: int = 0
var _prefetch: Array[Vector2i] = []
var _active_rect: Rect2i = Rect2i()
var _water_material: ShaderMaterial = null
var _foam_material: ShaderMaterial = null
var _shore_field: RefCounted = SHORE_FIELD.new()
var _field_reach: float = -1.0
var _last_transform: Transform2D = Transform2D()
var _last_viewport: Rect2 = Rect2()
var _view_dirty: bool = true
var _build_count: int = 0
var _hits: int = 0
var _misses: int = 0
var _evictions: int = 0
var _build_usec: int = 0
var _field_usec: int = 0


func _init() -> void:
	z_as_relative = false
	z_index = -80
	y_sort_enabled = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)


func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(refresh_view)


func _exit_tree() -> void:
	_clear_cache()
	if RenderingServer.frame_pre_draw.is_connected(refresh_view):
		RenderingServer.frame_pre_draw.disconnect(refresh_view)


func configure(solid_cells: Dictionary, shore_styles: Dictionary = {}, overrides: Array[Dictionary] = []) -> void:
	set_process(false)
	_clear_chunks()
	_solid_cells = solid_cells.duplicate()
	_shore_styles = shore_styles.duplicate()
	_shore_overrides = overrides.duplicate(true)
	_occupancy.clear()
	for cell: Vector2i in _solid_cells:
		var at: Vector2i = Vector2i((Vector2(cell) / CELLS_PER_CHUNK).floor())
		_occupancy[at] = int(_occupancy.get(at, 0)) + 1
	_build_count = 0
	_hits = 0
	_misses = 0
	_evictions = 0
	_build_usec = 0
	_field_usec = 0
	_field_reach = -1.0
	_water_material = ShaderMaterial.new()
	_water_material.shader = WATER_SHADER
	_foam_material = ShaderMaterial.new()
	_foam_material.shader = FOAM_SHADER
	if not apply_profile():
		_water_material = null
		_foam_material = null
		return
	set_process(true)
	refresh_view.call_deferred()


func apply_profile() -> bool:
	if profile == null or not profile.validation_error().is_empty():
		push_error("Water background: perfil invalido")
		return false
	if _water_material == null:
		return false
	var parameters: Dictionary = profile.shader_parameters()
	for key: String in parameters:
		_water_material.set_shader_parameter(key, parameters[key])
	_water_material.set_shader_parameter(&"use_shore_field", true)
	var foam_parameters: Dictionary = profile.foam_shader_parameters()
	for key: String in foam_parameters:
		_foam_material.set_shader_parameter(key, foam_parameters[key])
		_water_material.set_shader_parameter(key, foam_parameters[key])
	_water_material.set_shader_parameter(&"combined_foam", combine_foam and foam_enabled)
	# Beach is widest; the shader's spatial variance only narrows this bound.
	var reach: float = maxf(profile.shallow_width_px * 1.35, profile.foam_reach_px) + 2.0
	if not is_equal_approx(_field_reach, reach):
		_clear_chunks()
		_field_reach = reach
		_shore_field.call(&"configure", _solid_cells, reach, _shore_styles, _shore_overrides)
	else:
		for chunk: Node2D in _chunks.values():
			_set_foam_visibility(chunk)
		for chunk: Node2D in _cache.values():
			_set_foam_visibility(chunk)
	set_elapsed(elapsed)
	return true


func _process(delta: float) -> void:
	set_elapsed(elapsed + delta)
	_prepare_nearby()


func set_elapsed(seconds: float) -> void:
	if not is_finite(seconds):
		return
	elapsed = maxf(seconds, 0.0)
	if _water_material != null:
		_water_material.set_shader_parameter(&"water_elapsed", elapsed)
	if _foam_material != null:
		_foam_material.set_shader_parameter(&"water_elapsed", elapsed)


func refresh_view() -> void:
	if not is_inside_tree() or _water_material == null:
		return
	var canvas_transform: Transform2D = get_global_transform_with_canvas()
	var viewport_rect: Rect2 = get_viewport_rect()
	if not _view_dirty and canvas_transform == _last_transform and viewport_rect == _last_viewport:
		return
	_view_dirty = false
	_last_transform = canvas_transform
	_last_viewport = viewport_rect
	var inverse: Transform2D = canvas_transform.affine_inverse()
	var bounds: Rect2 = Rect2(inverse * viewport_rect.position, Vector2.ZERO)
	for point: Vector2 in [viewport_rect.position + Vector2(viewport_rect.size.x, 0), viewport_rect.end,
		viewport_rect.position + Vector2(0, viewport_rect.size.y)]:
		bounds = bounds.expand(inverse * point)
	update_visible_rect(bounds.grow(24.0))


func update_visible_rect(bounds: Rect2) -> void:
	var first: Vector2i = Vector2i((bounds.position / CHUNK_SIZE).floor())
	var last: Vector2i = Vector2i((bounds.end / CHUNK_SIZE).ceil())
	var wanted: Rect2i = Rect2i(first, last - first)
	if wanted == _active_rect:
		return
	_active_rect = wanted
	for coordinate: Vector2i in _chunks.keys():
		if not wanted.has_point(coordinate):
			var old: Node2D = _chunks[coordinate]
			remove_child(old)
			_chunks.erase(coordinate)
			_retire(coordinate, old)
	for y: int in range(first.y, last.y):
		for x: int in range(first.x, last.x):
			var coordinate: Vector2i = Vector2i(x, y)
			if _chunks.has(coordinate):
				continue
			var chunk: Node2D = null
			if _cache.has(coordinate):
				chunk = _cache[coordinate]
				_cache.erase(coordinate)
				_lru.erase(coordinate)
				_cache_bytes -= int(chunk.get_meta(&"bytes", 0))
				_hits += 1
			else:
				_misses += 1
				chunk = _build_chunk(coordinate)
			add_child(chunk)
			_chunks[coordinate] = chunk
	_prefetch.clear()
	var nearby: Rect2i = wanted.grow(prefetch_margin_chunks)
	for y: int in range(nearby.position.y, nearby.end.y):
		for x: int in range(nearby.position.x, nearby.end.x):
			var coordinate: Vector2i = Vector2i(x, y)
			if not _chunks.has(coordinate) and not _cache.has(coordinate):
				_prefetch.append(coordinate)
	var center: Vector2 = Vector2(wanted.get_center())
	_prefetch.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(center) < Vector2(b).distance_squared_to(center))


func _prepare_nearby() -> void:
	if prefetch_budget_usec <= 0 or cache_max_chunks <= 0 or cache_budget_mb <= 0.0:
		return
	var started: int = Time.get_ticks_usec()
	var count: int = 0
	while not _prefetch.is_empty() and Time.get_ticks_usec() - started < prefetch_budget_usec and count < 1:
		var coordinate: Vector2i = _prefetch.pop_front()
		if not _chunks.has(coordinate) and not _cache.has(coordinate):
			_retire(coordinate, _build_chunk(coordinate))
			count += 1


func _retire(coordinate: Vector2i, chunk: Node2D) -> void:
	_cache[coordinate] = chunk
	_lru.append(coordinate)
	_cache_bytes += int(chunk.get_meta(&"bytes", 0))
	while _lru.size() > cache_max_chunks or _cache_bytes > int(cache_budget_mb * 1048576.0):
		var oldest: Vector2i = _lru.pop_front()
		var victim: Node2D = _cache[oldest]
		_cache_bytes -= int(victim.get_meta(&"bytes", 0))
		_cache.erase(oldest)
		victim.free()
		_evictions += 1


func _clear_cache() -> void:
	for chunk: Node2D in _cache.values():
		chunk.free()
	_cache.clear()
	_lru.clear()
	_cache_bytes = 0
	_prefetch.clear()


func _clear_chunks() -> void:
	for chunk: Node2D in _chunks.values():
		remove_child(chunk)
		chunk.free()
	_chunks.clear()
	_clear_cache()
	_active_rect = Rect2i()
	_view_dirty = true


func water_rectangles(coordinate: Vector2i) -> Array[Rect2]:
	var occupied: int = int(_occupancy.get(coordinate, 0))
	if occupied == 0:
		return [Rect2(0, 0, CHUNK_SIZE, CHUNK_SIZE)]
	if occupied == CELLS_PER_CHUNK * CELLS_PER_CHUNK:
		return []
	var rectangles: Array[Rect2] = []
	var previous: Dictionary = {}
	var origin_cell: Vector2i = coordinate * CELLS_PER_CHUNK
	for y: int in range(CELLS_PER_CHUNK):
		var current: Dictionary = {}
		var start: int = -1
		for x: int in range(CELLS_PER_CHUNK + 1):
			var wet: bool = x < CELLS_PER_CHUNK and not _solid_cells.has(origin_cell + Vector2i(x, y))
			if wet and start < 0:
				start = x
			elif not wet and start >= 0:
				var run: Vector2i = Vector2i(start, x - start)
				var index: int = int(previous.get(run, -1))
				if index >= 0:
					var extended: Rect2 = rectangles[index]
					extended.size.y += CELL_SIZE
					rectangles[index] = extended
				else:
					index = rectangles.size()
					rectangles.append(Rect2(start * CELL_SIZE, y * CELL_SIZE, run.y * CELL_SIZE, CELL_SIZE))
				current[run] = index
				start = -1
		previous = current
	return rectangles


func _build_chunk(coordinate: Vector2i) -> Node2D:
	var started: int = Time.get_ticks_usec()
	var chunk: Node2D = Node2D.new()
	chunk.name = "Chunk_%d_%d" % [coordinate.x, coordinate.y]
	chunk.position = Vector2(coordinate * CHUNK_SIZE)
	var bytes: int = 0
	var rectangles: Array[Rect2] = water_rectangles(coordinate)
	if not rectangles.is_empty():
		var field_started: int = Time.get_ticks_usec()
		var field: Dictionary = _shore_field.call(&"build_chunk", coordinate)
		_field_usec += Time.get_ticks_usec() - field_started
		var vertices: PackedVector2Array = PackedVector2Array()
		var uvs: PackedVector2Array = PackedVector2Array()
		for rect: Rect2 in rectangles:
			_append_quad(vertices, uvs, rect, float(field.padding))
		var mesh: ArrayMesh = _make_mesh(vertices, uvs)
		_add_mesh(chunk, "Surface", mesh, field.texture as Texture2D, _water_material)
		if bool(field.has_shore):
			_add_mesh(chunk, "Foam", mesh, field.texture as Texture2D, _foam_material)
		_set_foam_visibility(chunk)
		bytes = int(field.bytes) + vertices.size() * 16
	chunk.set_meta(&"bytes", bytes)
	_build_count += 1
	_build_usec += Time.get_ticks_usec() - started
	return chunk


func _set_foam_visibility(chunk: Node2D) -> void:
	var foam: CanvasItem = chunk.get_node_or_null("Foam") as CanvasItem
	if foam != null:
		foam.visible = foam_enabled and not combine_foam


func _append_quad(vertices: PackedVector2Array, uvs: PackedVector2Array, rect: Rect2, padding: float) -> void:
	var points: Array[Vector2] = [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end,
		rect.position, rect.end, rect.position + Vector2(0, rect.size.y)]
	for point: Vector2 in points:
		vertices.append(point)
		uvs.append((point + Vector2(padding, padding)) / (CHUNK_SIZE + padding * 2.0))


func _make_mesh(vertices: PackedVector2Array, uvs: PackedVector2Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_mesh(parent_node: Node2D, node_name: String, mesh: ArrayMesh, field_texture: Texture2D, shader_material: ShaderMaterial) -> void:
	var instance: MeshInstance2D = MeshInstance2D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.texture = field_texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	instance.material = shader_material
	parent_node.add_child(instance)


func active_chunk_count() -> int:
	return _chunks.size()


func diagnostics() -> Dictionary:
	var active_bytes: int = 0
	for chunk: Node2D in _chunks.values():
		active_bytes += int(chunk.get_meta(&"bytes", 0))
	return {"active_chunks": _chunks.size(), "cache_chunks": _cache.size(), "cache_bytes": _cache_bytes,
		"active_bytes": active_bytes, "cache_hits": _hits, "cache_misses": _misses, "evictions": _evictions,
		"builds": _build_count, "build_ms": _build_usec / 1000.0, "field_ms": _field_usec / 1000.0,
		"prefetch_pending": _prefetch.size()}
