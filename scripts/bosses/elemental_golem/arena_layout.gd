extends Node2D
## Room_4_Elemental is the source of floor support, platform IDs, walls and art.
const MAP_SOURCE: Script = preload("res://scripts/bosses/elemental_golem/arena_map_source.gd")
const PAINTED_FLOOR: Script = preload("res://scripts/bosses/elemental_golem/arena_painted_floor.gd")
const TILES: Script = preload("res://scripts/bosses/elemental_golem/arena_tiles.gd")
const FACADE_FADE: Shader = preload("res://shaders/golem_facade_fade.gdshader")
const FLOOR_PALETTE: Shader = preload("res://shaders/golem_floor_palette.gdshader")
const MARKER: Script = preload("res://scripts/visual/booster_exclamation.gd")
const CAMERA_MARGIN: float = 256.0
var bounds: Rect2 = Rect2()
var hall: Rect2 = Rect2()
var entrance: Vector2 = Vector2.ZERO
var boss_spawn: Vector2 = Vector2.ZERO
var entrance_data: Dictionary = {}
var platforms: Array[Rect2] = []
var landing_point: Vector2 = Vector2.INF:
	set(value):
		landing_point = value
		_update_landing_warning()
var _landing_warning: AnimatedSprite2D
var _grid: int = 8
var _grid_origin: Vector2 = Vector2.ZERO
var _cells: Dictionary[Vector2i,int] = {}
var _regions: Dictionary[int,Rect2] = {}
var _wall_boxes: Array[Rect2] = []
var _layers: Array = []
var _tilesets: Dictionary = {}
var _tiles: RefCounted = TILES.new()
var adapted_to_painted_floor: bool = false
var _floor_points: Dictionary[int, PackedVector2Array] = {}
var _recovery_points: Dictionary[Vector2i, Vector2] = {}


func load_map(path: String, level_name: String) -> bool:
	var composition: Dictionary = MAP_SOURCE.read(path, level_name)
	if not bool(composition.get("ok",false)):
		push_error(str(composition.get("error","Elemental LDtk level missing")))
		return false
	var level: Dictionary = composition.primary as Dictionary
	_layers = composition.layers as Array
	# Preserve the combat field's centred coordinates; LDtk world offsets are editor-only.
	var origin: Vector2 = Vector2.ONE*(-float(level.pxWid)*0.5)
	bounds = Rect2(origin,Vector2(float(level.pxWid),float(level.pxHei)))
	for definition: Dictionary in composition.tilesets:
		_tilesets[int(definition.uid)] = definition
	var geometry: Dictionary = {}
	var found_entrance: bool = false
	var found_boss: bool = false
	for layer: Dictionary in _layers:
		if str(layer.__identifier) == "ElementalLayout": geometry = layer
		for entity: Dictionary in layer.get("entityInstances",[]):
			var point: Vector2 = origin+Vector2(float(entity.px[0]),float(entity.px[1]))
			if str(entity.__identifier) == "ElementalGolemSpawn":
				boss_spawn = point
				found_boss = true
			elif str(entity.__identifier) == "Warp":
				var fields: Dictionary = {}
				for field: Dictionary in entity.get("fieldInstances",[]): fields[str(field.__identifier)] = field.get("__value")
				if not bool(fields.get("IsEntrance",false)) and (found_entrance or str(fields.get("WarpId", "")) != "entry"): continue
				entrance = point
				entrance_data = fields
				entrance_data["position"] = point
				found_entrance = true
	if geometry.is_empty() or not found_entrance or not found_boss:
		push_error("Elemental LDtk: requires ElementalLayout, entrance Warp and ElementalGolemSpawn")
		return false
	_grid = int(geometry.__gridSize)
	_grid_origin = origin+Vector2(float(geometry.get("__pxTotalOffsetX",0)),float(geometry.get("__pxTotalOffsetY",0)))
	var columns: int = int(geometry.__cWid)
	var values: Array = geometry.intGridCsv as Array
	for index: int in range(values.size()):
		var cell: Vector2i = Vector2i(index%columns,floori(float(index)/columns))
		var value: int = int(values[index])
		_cells[cell] = value
	adapted_to_painted_floor = PAINTED_FLOOR.reconcile(_cells, _layers, _tilesets, _tiles.get("textures") as RefCounted,
		_grid, _grid_origin - origin)
	for cell: Vector2i in _cells:
		var value: int = _cells[cell]
		if value == 3 or (value >= 11 and value <= 19):
			var area: Rect2 = Rect2(_grid_origin+Vector2(cell)*_grid,Vector2.ONE*_grid)
			_regions[value] = (_regions[value] as Rect2).merge(area) if _regions.has(value) else area
			if not _floor_points.has(value): _floor_points[value] = PackedVector2Array()
			_floor_points[value].append(area.get_center())
	for index: int in range(9):
		if not _regions.has(11+index):
			push_error("Elemental LDtk: missing Platform_"+str(index+1))
			return false
		platforms.append(_regions[11+index])
	if not _regions.has(3):
		push_error("Elemental LDtk: missing Hall")
		return false
	hall = _regions[3]
	if _value_at(entrance) != 3 or _value_at(boss_spawn) < 11 or _value_at(boss_spawn) > 19:
		push_error("Elemental LDtk: place entrance in Hall and boss on a Platform")
		return false
	_merge_walls(columns,int(geometry.__cHei))
	return true


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_add_backdrop("Void", bounds.grow(2048), Color("171721"), -100)
	var chamber: Rect2 = platforms[0].merge(platforms[2]).merge(platforms[6]).merge(platforms[8])
	_add_backdrop("ArenaVoid", chamber, Color.BLACK, -99)
	_tiles.call("build",self,_layers,_tilesets,bounds.position)
	var facade: ShaderMaterial = ShaderMaterial.new()
	facade.shader = FACADE_FADE
	facade.set_shader_parameter(&"room_origin", to_global(bounds.position))
	var floor_palette: ShaderMaterial = ShaderMaterial.new()
	floor_palette.shader = FLOOR_PALETTE
	for child: Node in get_children():
		var layer: TileMapLayer = child as TileMapLayer
		if layer == null: continue
		var layer_name: String = str(layer.name)
		if layer_name.begins_with("GolemArenaGray_"):
			layer.material = facade
		elif layer_name.begins_with("Floor_Elemental_") or layer_name.begins_with("PlatformUnderside_") or layer_name.begins_with("TerrainCliffRim_"):
			layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			layer.material = floor_palette
	_build_walls()
	_landing_warning = AnimatedSprite2D.new()
	_landing_warning.name = "LandingWarning"
	_landing_warning.sprite_frames = MARKER.marker_frames(get_tree(), true)
	_landing_warning.scale = Vector2.ONE * 0.75
	_landing_warning.z_index = 9
	add_child(_landing_warning)
	_update_landing_warning()


func _add_backdrop(node_name: String, area: Rect2, color: Color, depth: int) -> void:
	var backdrop: Polygon2D = Polygon2D.new()
	backdrop.name = node_name
	backdrop.polygon = PackedVector2Array([
		area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y),
	])
	backdrop.color = color
	backdrop.z_index = depth
	add_child(backdrop)


func _merge_walls(columns: int, rows: int) -> void:
	var previous: Dictionary[Vector2i,Rect2] = {}
	for y: int in range(rows):
		var runs: Dictionary[Vector2i,Rect2] = {}
		var x: int = 0
		while x < columns:
			if _cells.get(Vector2i(x,y),0) != 2:
				x += 1
				continue
			var left: int = x
			while x < columns and _cells.get(Vector2i(x,y),0) == 2: x += 1
			var key: Vector2i = Vector2i(left,x-left)
			var box: Rect2 = Rect2(_grid_origin+Vector2(left,y)*_grid,Vector2(x-left,1)*_grid)
			runs[key] = (previous[key] as Rect2).merge(box) if previous.has(key) else box
		for key: Vector2i in previous:
			if not runs.has(key): _wall_boxes.append(previous[key])
		previous = runs
	for box: Rect2 in previous.values(): _wall_boxes.append(box)


func _build_walls() -> void:
	var boundary: StaticBody2D = StaticBody2D.new()
	boundary.name = "CastleWalls"
	boundary.collision_layer = 1
	boundary.collision_mask = 0
	add_child(boundary)
	for box: Rect2 in wall_rectangles():
		var collision: CollisionShape2D = CollisionShape2D.new()
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = box.size
		collision.shape = shape
		collision.position = box.get_center()
		boundary.add_child(collision)


func wall_rectangles() -> Array[Rect2]:
	return _wall_boxes


func _value_at(point: Vector2) -> int:
	var pixel: Vector2 = (point-_grid_origin)/float(_grid)
	return _cells.get(Vector2i(floori(pixel.x),floori(pixel.y)),1)


func supports_feet(point: Vector2) -> bool:
	var value: int = _value_at(to_local(point))
	return value == 3 or (value >= 11 and value <= 19)


func platform_at(point: Vector2) -> int:
	var value: int = _value_at(to_local(point))
	return value-11 if value >= 11 and value <= 19 else -1


func _closest_floor(point: Vector2, region: int = -1) -> Vector2:
	var result: Vector2 = entrance
	var distance: float = INF
	for value: int in _floor_points:
		if region >= 0 and value != region: continue
		for candidate: Vector2 in _floor_points[value]:
			var squared: float = candidate.distance_squared_to(point)
			if squared < distance:
				distance = squared
				result = candidate
	return result


func clamp_platform_point(point: Vector2, index: int) -> Vector2:
	return point if _value_at(point) == index+11 else _closest_floor(point,index+11)


func recovery_feet(world_point: Vector2) -> Vector2:
	var index: int = platform_at(world_point)
	var area: Rect2 = platforms[index] if index >= 0 else hall
	# Keep the player's capsule inside the last floor, rather than on its lip.
	var safe_area: Rect2 = area.grow(-10.0)
	var candidate: Vector2 = to_local(world_point).clamp(safe_area.position,safe_area.end)
	var region: int = index+11 if index >= 0 else 3
	if _value_at(candidate) == region: return to_global(candidate)
	var cell: Vector2i = Vector2i((to_local(world_point) - _grid_origin) / float(_grid))
	if not _recovery_points.has(cell): _recovery_points[cell] = _closest_floor(candidate, region)
	return to_global(_recovery_points[cell])


func safe_floor_near(point: Vector2) -> Vector2:
	var index: int = platform_at(point)
	var area: Rect2 = platforms[index] if index >= 0 else hall
	var local: Vector2 = to_local(point)
	var inset: Rect2 = area.grow(-22.0)
	var offset: Vector2 = Vector2(52, 30) if local.x < area.get_center().x else Vector2(-52, -30)
	var candidate: Vector2 = (local+offset).clamp(inset.position,inset.end)
	var region: int = index+11 if index >= 0 else 3
	return to_global(candidate if _value_at(candidate) == region else _closest_floor(candidate,region))


func _update_landing_warning() -> void:
	if _landing_warning == null: return
	_landing_warning.visible = landing_point.is_finite()
	if _landing_warning.visible:
		_landing_warning.position = to_local(landing_point).round()
		_landing_warning.play(&"idle")
	else:
		_landing_warning.stop()
