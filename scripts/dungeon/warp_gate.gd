extends Node2D
## Authored warp, static yellow inlays and a centre-aligned arrival point.

signal travel_requested(gate: Node2D)
const VISUAL: Script = preload("res://scripts/visual/warp_visual.gd")
const ACTION_PROMPT: Script = preload("res://scripts/visual/world_action_prompt.gd")
const PLATFORM: Script = preload("res://scripts/dungeon/central_warp_platform.gd")
var data: Dictionary = {}
var actor: Player = null
var gameplay: Node2D = null
var _armed: bool = false
var _plate: Sprite2D = null
var _visual: Node2D = null
var _action: Sprite2D = null
var _platform: Node2D = null


func configure(description: Dictionary, texture: Texture2D) -> void:
	data = description
	position = data.position
	z_index = -15
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled = true
	_visual = VISUAL.new() as Node2D
	_visual.name = "Presentation"
	var display_scale: float = clampf(float(data.get("DisplayScale", 1.0 if bool(data.get("Central", false)) else 0.5)), 0.125, 4.0)
	_visual.call("configure", bool(data.get("Central", false)), texture, display_scale)
	add_child(_visual)
	_plate = _visual.get("plate") as Sprite2D
	if bool(data.get("Central", false)):
		_platform = PLATFORM.new() as Node2D
		_platform.name = "Platform"
		_platform.call("configure", _visual, data)
		add_child(_platform)
	_action = ACTION_PROMPT.new() as Sprite2D
	_action.name = "ActionPrompt"
	add_child(_action)
	_action.call("configure", Vector2(0, roundf((-121.0 if bool(data.get("Central", false)) else -51.0) * display_scale)))


func spawn_position() -> Vector2:
	return position - VISUAL.FEET_OFFSET + Vector2(0, float(_platform.get("elevation")) if _platform != null else 0.0)


func supports_feet(world_feet: Vector2) -> bool:
	if _platform != null:
		return bool(_platform.call("supports_feet", world_feet))
	return _visual != null and bool(_visual.call("supports_feet", _visual.to_local(world_feet)))


func height_at(world_feet: Vector2) -> float:
	return float(_platform.call("height_at", world_feet)) if _platform != null else 0.0


func _physics_process(_delta: float) -> void:
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
