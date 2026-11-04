extends Node2D
## LDtk adapter and scene wiring. River geometry itself is engine-data only.

const CONTOUR: Script = preload("res://scripts/visual/river_contour.gd")
var contour: RefCounted = null
var diagnostics: Array[String] = []
var edge_softness_px: float = 1.0
var west_bank_start_y: float = -INF


func configure(layers: Array, descriptions: Array, softness: float) -> bool:
	edge_softness_px = clampf(softness, 0.25, 1.5)
	var rivers: Array[Dictionary] = []
	for description: Dictionary in descriptions:
		if str(description.get("preset", "")) == "River":
			rivers.append(description)
	var wet: Dictionary = {}
	var decks: Dictionary = {}
	var west_lock: float = -INF
	west_bank_start_y = -INF
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)): continue
		var name_in_map: String = str(layer.get("__identifier", ""))
		if name_in_map == "RiverMask":
			var width: int = int(layer.get("__cWid", 1))
			var values: Array = layer.get("intGridCsv", []) as Array
			for index: int in range(values.size()):
				if int(values[index]) == 1: wet[Vector2i(index % width, floori(float(index) / width))] = true
		if name_in_map == "Floor_Bridges":
			for tile: Dictionary in layer.get("gridTiles", []): decks[Vector2i(int(tile.px[0]), int(tile.px[1]))] = true
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) == "ElevationArea":
				west_bank_start_y = maxf(west_bank_start_y, float(entity.px[1]) + float(entity.height))
				west_lock = maxf(west_lock, float(entity.px[1]) + float(entity.height) + 32.0)
	if wet.is_empty():
		diagnostics.append("RiverMask ausente/vazia; margem original mantida.")
		return false
	if rivers.size() != 1:
		diagnostics.append("O contorno do rio exige uma unica WaterArea com preset River.")
		return false
	var spans: Array[Rect2] = []
	while not decks.is_empty():
		var first: Vector2i = decks.keys()[0] as Vector2i
		var queue: Array[Vector2i] = [first]
		decks.erase(first)
		var start: Vector2i = first
		var ending: Vector2i = first
		while not queue.is_empty():
			var point: Vector2i = queue.pop_back() as Vector2i
			start = start.min(point)
			ending = ending.max(point)
			for delta: Vector2i in [Vector2i(16, 0), Vector2i(-16, 0), Vector2i(0, 16), Vector2i(0, -16)]:
				if decks.has(point + delta):
					decks.erase(point + delta)
					queue.append(point + delta)
		spans.append(Rect2(Vector2(start), Vector2(ending - start + Vector2i(16, 16))))
	spans.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y)
	contour = CONTOUR.new()
	if not bool(contour.call("configure", wet, rivers[0].rect as Rect2, spans, west_lock)):
		diagnostics.assign(contour.get("diagnostics") as Array[String])
		contour = null
		return false
	return true


func _parameters(shader_material: ShaderMaterial) -> void:
	if contour == null or shader_material == null: return
	var rect: Rect2 = contour.get("bounds") as Rect2
	shader_material.set_shader_parameter(&"river_contour_enabled", true)
	shader_material.set_shader_parameter(&"river_profile", contour.get("profile_texture"))
	shader_material.set_shader_parameter(&"river_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	shader_material.set_shader_parameter(&"river_world_origin", global_position)
	shader_material.set_shader_parameter(&"river_profile_count", (contour.get("samples") as PackedVector4Array).size())
	shader_material.set_shader_parameter(&"river_profile_step", 2.0)
	shader_material.set_shader_parameter(&"river_edge_softness_px", edge_softness_px)
	shader_material.set_shader_parameter(&"river_west_bank_start_y", west_bank_start_y if is_finite(west_bank_start_y) else -1e20)


func bind_ground(surfaces: Array[TileMapLayer], cloud_clock: Node, floor_cells: Dictionary, ground_texture: Texture2D) -> void:
	if contour == null or cloud_clock == null: return
	var variants: Dictionary[int, ShaderMaterial] = {}
	for surface: TileMapLayer in surfaces:
		var layer_name: String = str(surface.name)
		if not layer_name.begins_with("Floor_") or layer_name.begins_with("Floor_Bridges") or layer_name.begins_with("Floor_Castle"): continue
		var original: ShaderMaterial = surface.material as ShaderMaterial
		if original == null: continue
		var key: int = original.get_instance_id()
		if not variants.has(key):
			var clipped: ShaderMaterial = original.duplicate() as ShaderMaterial
			_parameters(clipped)
			variants[key] = clipped
			cloud_clock.call("register_material", clipped)
		surface.material = variants[key]
	# Reclaimed slivers need actual ground, not a blank quad over the whole map.
	# Only original river void cells receive this single batched fill mesh.
	var vertices: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var rect: Rect2 = contour.get("bounds") as Rect2
	var first: Vector2i = Vector2i((rect.position / 16.0).ceil())
	var end: Vector2i = Vector2i((rect.end / 16.0).floor())
	var valid_y: Vector2 = contour.get("valid_y") as Vector2
	for y: int in range(maxi(first.y, floori(valid_y.x / 16.0)), mini(end.y, floori(valid_y.y / 16.0))):
		var furthest_west_land: float = -INF
		var furthest_east_land: float = INF
		for sample_y: int in range(y * 16, y * 16 + 17, 2):
			var banks: Vector4 = contour.call("banks_at", float(sample_y)) as Vector4
			if banks.z > 0.0: furthest_west_land = maxf(furthest_west_land, banks.x + 1.0)
			if banks.w > 0.0: furthest_east_land = minf(furthest_east_land, banks.y - 1.0)
		for x: int in range(first.x, end.x):
			if floor_cells.has(Vector2i(x, y)): continue
			if x * 16 >= furthest_west_land and (x + 1) * 16 <= furthest_east_land: continue
			var i: int = vertices.size()
			var origin: Vector2 = Vector2(x * 16, y * 16)
			vertices.append_array(PackedVector2Array([origin, origin + Vector2(16, 0), origin + Vector2(16, 16), origin + Vector2(0, 16)]))
			uvs.append_array(PackedVector2Array([Vector2.ONE * 0.5, Vector2.ONE * 0.5, Vector2.ONE * 0.5, Vector2.ONE * 0.5]))
			indices.append_array(PackedInt32Array([i, i + 1, i + 2, i, i + 2, i + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var fill: MeshInstance2D = MeshInstance2D.new()
	fill.name = "GroundFill"
	fill.mesh = mesh
	fill.set_meta(&"quad_count", floori(indices.size() / 6.0))
	fill.texture = ground_texture
	fill.z_as_relative = false
	fill.z_index = -21
	var palette_materials: Dictionary = cloud_clock.get("palette_materials") as Dictionary
	var source: ShaderMaterial = palette_materials.get(4) as ShaderMaterial
	var fill_material: ShaderMaterial = source.duplicate() as ShaderMaterial
	_parameters(fill_material)
	fill_material.set_shader_parameter(&"river_ground_fill", true)
	cloud_clock.call("register_material", fill_material)
	fill.material = fill_material
	add_child(fill)


func bind_water(water: Node2D, foam: bool) -> void:
	if contour == null: return
	for region: Node2D in water.get("regions") as Array[Node2D]:
		if str(region.get_meta(&"preset", "")) != "River": continue
		var sprite: Sprite2D = region.get_node("Surface") as Sprite2D
		var water_material: ShaderMaterial = sprite.material as ShaderMaterial
		_parameters(water_material)
		for appearance: WaterProfile in water.get("profiles") as Array[WaterProfile]:
			if str(appearance.preset_id) != str(region.get_meta(&"preset", "")): continue
			var foam_parameters: Dictionary = appearance.foam_shader_parameters()
			for key: String in foam_parameters:
				water_material.set_shader_parameter(key, foam_parameters[key])
		water_material.set_shader_parameter(&"combined_foam", foam)


func add_collision(parent: StaticBody2D) -> void:
	if contour == null: return
	var segments: PackedVector2Array = contour.call("collision_segments") as PackedVector2Array
	var shape: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
	shape.segments = segments
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "RiverBanks"
	collision.shape = shape
	parent.add_child(collision)


func replaces_grid_edge(point: Vector2) -> bool:
	return contour != null and bool(contour.call("replaces_edge", point))


func transition_shape(point: Vector2, direction: Vector2i) -> Shape2D:
	if contour == null or direction.x == 0: return null
	var top: bool = bool(contour.call("replaces_edge", point - Vector2(0, 8)))
	var bottom: bool = bool(contour.call("replaces_edge", point + Vector2(0, 8)))
	if top == bottom: return null
	# Join the existing 4 px cliff blocker to the zero-width curved segment.
	# A rectangular cap would otherwise protrude 2 px into the low river.
	var shape: ConvexPolygonShape2D = ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([Vector2(0, -8), Vector2(2, 8), Vector2(-2, 8)]) if top else PackedVector2Array([Vector2(-2, -8), Vector2(2, -8), Vector2(0, 8)])
	return shape


func ground_override(point: Vector2) -> int:
	return int(contour.call("ground_override", point)) if contour != null else -1


func update_allowed_cells(cells: Dictionary) -> void:
	if contour == null: return
	var rect: Rect2 = contour.get("bounds") as Rect2
	var first: Vector2i = Vector2i((rect.position / 16.0).ceil())
	var end: Vector2i = Vector2i((rect.end / 16.0).floor())
	for y: int in range(first.y, end.y):
		for x: int in range(first.x, end.x):
			var cell: Vector2i = Vector2i(x, y)
			var result: int = ground_override(Vector2(cell * 16) + Vector2.ONE * 8.0)
			if result == 1: cells[cell] = true
			elif result == 0: cells.erase(cell)
