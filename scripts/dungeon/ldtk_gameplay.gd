extends Node2D
## Gameplay rules: collisions, traversal, room flow, and reserved hazard cells.

signal player_fell(body: Node2D)
signal end_reached(body: Node2D)
signal condition_changed(condition_id: String, satisfied: bool)

const TILE_SIZE: int = 16
const MAP_LIMIT: int = 1
const DASH_GAP: int = 2
const DOOR_BLOCK: int = 3
const DOORS: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
const START: int = 4
const END: int = 5
const SOLID: int = 6
const HAZARD: int = 7

var gap_cells: Dictionary[Vector2i, bool] = {}
var gap_rects: Array[Rect2] = []
var start_position: Vector2 = Vector2.ZERO
var has_start: bool = false
var doors_locked: bool = true
var _gap_area: Area2D
var _end_area: Area2D
var _start_area: Area2D
var _doors: StaticBody2D = null
var _condition_triggers: Array[Dictionary] = []


func configure(layers: Array) -> void:
	var solids: StaticBody2D = _body("MapLimits", &"ldtk_map_limits")
	_doors = DOORS.new() as StaticBody2D
	_doors.name = "DoorBlocks"
	_doors.collision_layer = 1
	_doors.collision_mask = 0
	_doors.add_to_group(&"ldtk_door_blocks")
	_doors.set("doors_locked",doors_locked)
	add_child(_doors)
	_doors.connect("condition_changed",func(key: String, met: bool) -> void: condition_changed.emit(key,met))
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
					MAP_LIMIT, SOLID, HAZARD: _rectangle(solids, rect)
					DASH_GAP: _add_gap(rect)
					DOOR_BLOCK: _doors.call("add_cell",rect)
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
				if identifier in ["DashGapArea", "DoorDash"]:
					var size: Vector2 = Vector2(float(entity.get("width", 32)), float(entity.get("height", 48)))
					var pivot: Array = entity.get("__pivot", [0, 0])
					_add_gap(Rect2(point - size * Vector2(float(pivot[0]), float(pivot[1])), size))
				elif identifier == "NoxStart":
					start_sum += point
					start_count += 1
				elif identifier == "GameplayTrigger" and bool(layer.get("visible",true)):
					_add_condition_trigger(entity,offset)
	if start_count > 0:
		start_position = start_sum / float(start_count)
		has_start = true
	set_doors_locked(doors_locked)
	_doors.call("configure_controls",layers)
	_gap_area.body_entered.connect(_on_gap_entered)
	_start_area.body_entered.connect(_on_start_entered)
	_end_area.body_entered.connect(func(body: Node2D) -> void: end_reached.emit(body))


func _physics_process(_delta: float) -> void:
	for trigger: Dictionary in _condition_triggers:
		if bool(trigger.done):
			continue
		var inside: bool = false
		for body: Node2D in (trigger.area as Area2D).get_overlapping_bodies():
			var player: Player = body as Player
			if player != null and not player.dead and not player.intro_locked:
				inside = true
				break
		if inside and not bool(trigger.inside):
			set_condition(str(trigger.condition_id),bool(trigger.value))
			trigger["done"] = bool(trigger.once)
		trigger["inside"] = inside
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
	if _doors != null:
		_doors.call("set_doors_locked",locked)


func set_door_region_locked(region: Rect2i, locked: bool) -> void:
	_doors.call("set_door_region_locked",region,locked)


func set_door_locked(door_id: String, locked: bool) -> void:
	_doors.call("set_door_locked",door_id,locked)


func is_door_cell_locked(cell: Vector2i) -> bool:
	return bool(_doors.call("is_door_cell_locked",cell))


func get_door_cell_count() -> int:
	return int(_doors.call("get_door_cell_count"))


func set_condition(condition_id: String, satisfied: bool = true) -> void:
	_doors.call("set_condition",condition_id,satisfied)


func is_condition_met(condition_id: String) -> bool:
	return bool(_doors.call("is_condition_met",condition_id))


func _add_condition_trigger(entity: Dictionary, offset: Vector2) -> void:
	var config: Dictionary = DOORS.fields(entity)
	var condition_id: String = str(config.get("ConditionId","")).strip_edges()
	if condition_id.is_empty() or not bool(config.get("Enabled",true)):
		return
	var area: Area2D = _area("ConditionTrigger_%d" % _condition_triggers.size(),&"ldtk_condition_triggers")
	_rectangle(area,DOORS.entity_rect(entity,offset))
	_condition_triggers.append({"area":area,"condition_id":condition_id,
		"value":bool(config.get("ConditionValue",true)),"once":bool(config.get("Once",true)),
		"inside":false,"done":false})


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
