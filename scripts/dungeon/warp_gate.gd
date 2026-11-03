extends Node2D
## Flat authored warp sprite. Its opaque footprint triggers travel, without elevation.

signal travel_requested(gate: Node2D)
const SPAWN_OFFSET: Vector2 = Vector2(0,-10)
const CIRCULATION: Script = preload("res://scripts/visual/warp_circulation.gd")
const ACTION_PROMPT: Script = preload("res://scripts/visual/world_action_prompt.gd")
var data: Dictionary = {}
var actor: Player = null
var gameplay: Node2D = null
var _ring: Node2D = null
var _armed: bool = false
var _plate: Sprite2D = null
var _surface_image: Image = null
var _surface_pixels: Rect2 = Rect2()
var _action: Sprite2D = null


func configure(description: Dictionary, texture: Texture2D) -> void:
	data = description
	position = data.position
	z_index = -15
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_plate = Sprite2D.new()
	_plate.name = "Plate"
	_plate.texture = texture
	_plate.centered = false
	add_child(_plate)
	_action = ACTION_PROMPT.new() as Sprite2D
	_action.name = "ActionPrompt"
	add_child(_action)
	_refresh_surface()
	if texture != null:
		texture.changed.connect(_refresh_surface)
	if bool(data.get("WhiteRing", false)):
		_ring = CIRCULATION.new() as Node2D
		_ring.name = "WhiteCirculation"
		_ring.visible = false
		add_child(_ring)
		_update_circulation_size()


func spawn_position() -> Vector2:
	return position + SPAWN_OFFSET


func _refresh_surface() -> void:
	_surface_image = null
	_surface_pixels = Rect2()
	if _plate.texture == null:
		return
	var source: Image = _plate.texture.get_image()
	if source == null or source.is_empty():
		return
	if source.is_compressed() and source.decompress() != OK:
		return
	_surface_image = source
	_plate.position = -Vector2(source.get_size())*0.5
	var used: Rect2i = source.get_used_rect()
	_surface_pixels = Rect2(used)
	_action.call("configure", Vector2(0, minf(-45.0, _plate.position.y - 13.0)))
	_update_circulation_size()


func _update_circulation_size() -> void:
	if _ring != null and _surface_pixels.has_area():
		_ring.call("configure", _surface_pixels.size * 0.25, _plate.position + _surface_pixels.get_center())


func supports_feet(world_feet: Vector2) -> bool:
	if _surface_image == null:
		return false
	var pixel: Vector2 = to_local(world_feet)-_plate.position
	return _supports_pixel(pixel)


func _supports_pixel(pixel: Vector2) -> bool:
	return _surface_pixels.has_point(pixel) and _surface_image.get_pixel(floori(pixel.x),floori(pixel.y)).a >= 0.5


func _physics_process(_delta: float) -> void:
	if _ring != null:
		_ring.visible = condition_satisfied()
	if _action != null:
		_action.call("set_available", can_interact())
	if not is_instance_valid(actor):
		return
	var inside: bool = supports_feet(actor.to_global(Vector2(0,3)))
	if not inside:
		_armed = true
		return
	if _armed and not bool(data.get("Interact", false)) and can_travel():
		_armed = false
		travel_requested.emit(self)


func condition_satisfied() -> bool:
	var requirement: String = str(data.get("RequiredCondition", ""))
	return requirement.is_empty() or (is_instance_valid(gameplay) and bool(gameplay.call("is_condition_met", requirement)))


func can_travel() -> bool:
	return is_instance_valid(actor) and not actor.intro_locked and not actor.dead \
		and (not str(data.get("TargetLevel", "")).is_empty() or not str(data.get("TargetScene", "")).is_empty()) \
		and condition_satisfied()


func can_interact() -> bool:
	return bool(data.get("Interact", false)) and can_travel() \
		and supports_feet(actor.to_global(Vector2(0, 3)))


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or not bool(data.get("Interact", false)):
		return
	if key.physical_keycode != KEY_E and key.keycode != KEY_E:
		return
	if can_interact():
		_armed = false
		_action.call("set_available", false)
		get_viewport().set_input_as_handled()
		travel_requested.emit(self)
