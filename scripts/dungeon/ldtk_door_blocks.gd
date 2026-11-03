extends StaticBody2D
## DoorBlock cells, independent regions and named room conditions, based on MonsterShift.

signal condition_changed(condition_id: String, satisfied: bool)
signal doors_changed
const TILE_SIZE: int = 16
var doors_locked: bool = true
var _shapes: Dictionary[Vector2i, CollisionShape2D] = {}
var _visuals: Dictionary[Vector2i, Polygon2D] = {}
var _rects: Dictionary[Vector2i, Rect2] = {}
var _locked: Dictionary[Vector2i, bool] = {}
var _conditions: Dictionary[String, bool] = {}
var _requirements: Dictionary[Vector2i, Array] = {}
var _named_regions: Dictionary[String, Array] = {}


static func fields(entity: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: Dictionary in entity.get("fieldInstances",[]):
		if field.get("__value") != null:
			result[str(field.get("__identifier",""))] = field["__value"]
	return result


static func entity_rect(entity: Dictionary, offset: Vector2) -> Rect2:
	var pixel: Array = entity.get("px",[0,0])
	var pivot: Array = entity.get("__pivot",[0,0])
	var size: Vector2 = Vector2(float(entity.get("width",16)),float(entity.get("height",16)))
	return Rect2(Vector2(float(pixel[0]),float(pixel[1]))+offset-size*Vector2(float(pivot[0]),float(pivot[1])),size)


func add_cell(rect: Rect2) -> void:
	var cell: Vector2i = Vector2i((rect.get_center()/TILE_SIZE).floor())
	if _shapes.has(cell):
		return
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "Block_%d_%d" % [cell.x,cell.y]
	collision.shape = shape
	collision.position = rect.get_center()
	collision.disabled = not doors_locked
	add_child(collision)
	var visual: Polygon2D = Polygon2D.new()
	visual.name = "Door_%d_%d" % [cell.x,cell.y]
	visual.position = rect.position
	visual.polygon = PackedVector2Array([Vector2.ZERO,Vector2(rect.size.x,0),rect.size,Vector2(0,rect.size.y)])
	visual.color = Color(0.96,0.57,0.18,0.72)
	visual.z_index = 1
	visual.visible = doors_locked
	add_child(visual)
	_shapes[cell] = collision
	_visuals[cell] = visual
	_rects[cell] = rect
	_locked[cell] = doors_locked


func configure_controls(layers: Array) -> void:
	for layer: Dictionary in layers:
		if not bool(layer.get("visible",true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX",0)),float(layer.get("__pxTotalOffsetY",0)))
		for entity: Dictionary in layer.get("entityInstances",[]):
			if str(entity.get("__identifier","")) != "DoorControl":
				continue
			var config: Dictionary = fields(entity)
			if not bool(config.get("Enabled",true)):
				continue
			var region: Rect2 = entity_rect(entity,offset)
			var door_id: String = str(config.get("DoorId","exit")).strip_edges()
			var condition_id: String = str(config.get("ConditionId","room_clear")).strip_edges()
			for cell: Vector2i in _rects:
				if not region.has_point(_rects[cell].get_center()):
					continue
				if not door_id.is_empty():
					if not _named_regions.has(door_id):
						_named_regions[door_id] = []
					if not cell in _named_regions[door_id]:
						_named_regions[door_id].append(cell)
				if not condition_id.is_empty():
					if not _requirements.has(cell):
						_requirements[cell] = []
					if not condition_id in _requirements[cell]:
						_requirements[cell].append(condition_id)


func set_condition(condition_id: String, satisfied: bool = true) -> void:
	var key: String = condition_id.strip_edges()
	if key.is_empty():
		return
	var changed: bool = not _conditions.has(key) or _conditions[key] != satisfied
	_conditions[key] = satisfied
	for cell: Vector2i in _requirements:
		if not key in _requirements[cell]:
			continue
		var all_met: bool = true
		for requirement: String in _requirements[cell]:
			all_met = all_met and is_condition_met(requirement)
		_set_cell_locked(cell,not all_met)
	if changed:
		condition_changed.emit(key,satisfied)


func is_condition_met(condition_id: String) -> bool:
	return bool(_conditions.get(condition_id.strip_edges(),false))


func set_doors_locked(locked: bool) -> void:
	doors_locked = locked
	for cell: Vector2i in _shapes:
		_set_cell_locked(cell,locked)


func set_door_region_locked(region: Rect2i, locked: bool) -> void:
	for cell: Vector2i in _shapes:
		if region.has_point(cell):
			_set_cell_locked(cell,locked)


func set_door_locked(door_id: String, locked: bool) -> void:
	for cell: Vector2i in _named_regions.get(door_id,[]):
		_set_cell_locked(cell,locked)


func is_door_cell_locked(cell: Vector2i) -> bool:
	return bool(_locked.get(cell,false))


func get_door_cell_count() -> int:
	return _shapes.size()


func _set_cell_locked(cell: Vector2i, locked: bool) -> void:
	var changed: bool = _locked[cell] != locked
	_locked[cell] = locked
	_shapes[cell].set_deferred("disabled",not locked)
	_visuals[cell].visible = locked
	if changed:
		doors_changed.emit()
