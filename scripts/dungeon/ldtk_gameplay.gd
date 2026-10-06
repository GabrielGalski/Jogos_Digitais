extends Node2D
## Door Dash/Gameplay rules adapted from MonsterShift's LdtkFloorRuntime.

signal player_fell(body: Node2D)
signal end_reached(body: Node2D)

const TILE_SIZE: int = 16
const MAP_LIMIT: int = 1
const DASH_GAP: int = 2
const DOOR_BLOCK: int = 3
const START: int = 4
const END: int = 5

var gap_cells: Dictionary[Vector2i, bool] = {}
var gap_rects: Array[Rect2] = []
var start_position: Vector2 = Vector2.ZERO
var has_start: bool = false
var doors_locked: bool = false
var _gap_area: Area2D
var _end_area: Area2D
var _start_area: Area2D
var _doors: Array[CollisionShape2D] = []


func configure(layers: Array) -> void:
	var solids: StaticBody2D = _body("MapLimits", &"ldtk_map_limits")
	var doors: StaticBody2D = _body("DoorBlocks", &"ldtk_door_blocks")
	_gap_area = _area("DashGaps", &"ldtk_dash_gaps")
	_end_area = _area("Ends", &"ldtk_ends")
	_start_area = _area("Starts", &"ldtk_starts")
	var start_sum: Vector2 = Vector2.ZERO
	var start_count: int = 0
	for layer: Dictionary in layers:
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		if str(layer.get("__identifier", "")) == "Gameplay":
			var width: int = int(layer.get("__cWid", 1))
			var grid: int = int(layer.get("__gridSize", TILE_SIZE))
			var values: Array = layer.get("intGridCsv", [])
			for index: int in range(values.size()):
				var point: Vector2 = Vector2(index % width, floori(float(index) / width)) * grid + offset
				var rect: Rect2 = Rect2(point, Vector2.ONE * grid)
				match int(values[index]):
					MAP_LIMIT: _rectangle(solids, rect)
					DASH_GAP: _add_gap(rect)
					DOOR_BLOCK: _doors.append(_rectangle(doors, rect))
					START:
						_rectangle(_start_area, rect)
						start_sum += rect.get_center()
						start_count += 1
					END: _rectangle(_end_area, rect)
		if str(layer.get("__type", "")) == "Entities":
			for entity: Dictionary in layer.get("entityInstances", []):
				var pixel: Array = entity.get("px", [0, 0])
				var point: Vector2 = Vector2(float(pixel[0]), float(pixel[1])) + offset
				var identifier: String = str(entity.get("__identifier", ""))
				if identifier == "DoorDash":
					var size: Vector2 = Vector2(float(entity.get("width", 32)), float(entity.get("height", 48)))
					var pivot: Array = entity.get("__pivot", [0, 0])
					_add_gap(Rect2(point - size * Vector2(float(pivot[0]), float(pivot[1])), size))
				elif identifier == "NoxStart":
					start_sum += point
					start_count += 1
	if start_count > 0:
		start_position = start_sum / float(start_count)
		has_start = true
	set_doors_locked(doors_locked)
	_gap_area.body_entered.connect(_on_gap_entered)
	_start_area.body_entered.connect(_on_start_entered)
	_end_area.body_entered.connect(func(body: Node2D) -> void: end_reached.emit(body))


func _physics_process(_delta: float) -> void:
	if _gap_area == null:
		return
	for body: Node2D in _gap_area.get_overlapping_bodies():
		_check_gap(body)


func _on_gap_entered(body: Node2D) -> void:
	_check_gap(body)


func _check_gap(body: Node2D) -> void:
	if not body.has_method(&"is_dashing") or bool(body.call(&"is_dashing")):
		return
	if not is_gap_point(to_local(body.global_position)):
		return
	if body.has_method(&"fall_from_ldtk_gap"):
		body.call_deferred(&"fall_from_ldtk_gap")
		player_fell.emit(body)


func is_gap_point(point: Vector2) -> bool:
	for rect: Rect2 in gap_rects:
		if rect.has_point(point):
			return true
	return false


func is_gap_cell(cell: Vector2i) -> bool:
	return gap_cells.has(cell)


func _add_gap(rect: Rect2) -> void:
	gap_rects.append(rect)
	_rectangle(_gap_area, rect)
	var first: Vector2i = Vector2i(floori(rect.position.x / TILE_SIZE), floori(rect.position.y / TILE_SIZE))
	var last: Vector2i = Vector2i(ceili(rect.end.x / TILE_SIZE), ceili(rect.end.y / TILE_SIZE))
	for y: int in range(first.y, last.y):
		for x: int in range(first.x, last.x):
			var cell: Vector2i = Vector2i(x, y)
			if rect.has_point(Vector2(cell * TILE_SIZE) + Vector2.ONE * 8.0):
				gap_cells[cell] = true


func _on_start_entered(body: Node2D) -> void:
	if has_start and body.has_method(&"set_respawn_position"):
		body.call(&"set_respawn_position", body.get_parent().to_local(to_global(start_position)))


func set_doors_locked(locked: bool) -> void:
	doors_locked = locked
	for collision: CollisionShape2D in _doors:
		collision.set_deferred(&"disabled", not locked)


func _body(node_name: String, group_name: StringName) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group(group_name)
	add_child(body)
	return body


func _area(node_name: String, group_name: StringName) -> Area2D:
	var area: Area2D = Area2D.new()
	area.name = node_name
	area.collision_layer = 0
	area.collision_mask = 1
	area.add_to_group(group_name)
	add_child(area)
	return area


func _rectangle(parent: Node2D, rect: Rect2) -> CollisionShape2D:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.shape = shape
	collision.position = rect.get_center()
	parent.add_child(collision)
	return collision
