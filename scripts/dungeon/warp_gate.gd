extends Node2D
## Authored warp, shared interaction and a centre-aligned arrival point.

signal travel_requested(gate: Node2D)
const VISUAL: Script = preload("res://scripts/visual/warp_visual.gd")
const ACTION_PROMPT: Script = preload("res://scripts/visual/world_action_prompt.gd")
const PLATFORM: Script = preload("res://scripts/dungeon/central_warp_platform.gd")
var data: Dictionary = {}
var actor: Player = null
var gameplay: Node2D = null
var travel_available: Callable
var _armed: bool = false
var _visual: Node2D = null
var _action: Sprite2D = null
var _platform: Node2D = null


func configure(description: Dictionary) -> void:
	data = description
	position = data.position
	z_index = -15
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled = true
	_visual = VISUAL.new() as Node2D
	_visual.name = "Presentation"
	var is_central: bool = bool(data.get("Central", false))
	var display_scale: float = clampf(float(data.get("DisplayScale", 1.0 if is_central else VISUAL.SMALL_SCALE)), 0.125, 4.0)
	var ground_height: float = float(data.get("GroundHeight", 0.0))
	_visual.call("configure", is_central, display_scale)
	_visual.position.y = -ground_height
	add_child(_visual)
	if is_central:
		_platform = PLATFORM.new() as Node2D
		_platform.name = "Platform"
		_platform.call("configure", _visual, data)
		add_child(_platform)
	_action = ACTION_PROMPT.new() as Sprite2D
	_action.name = "ActionPrompt"
	add_child(_action)
	var prompt_height: float = -121.0 * display_scale if is_central else -23.0 * display_scale - 5.0
	_action.call("configure", Vector2(0, roundf(prompt_height - ground_height)))


func spawn_position() -> Vector2:
	return position - VISUAL.FEET_OFFSET + Vector2(0, float(_platform.get("elevation")) if _platform != null else 0.0)


func supports_feet(world_feet: Vector2) -> bool:
	if _platform != null:
		return bool(_platform.call("supports_feet", world_feet))
	return _visual != null and bool(_visual.call("supports_feet", to_local(world_feet) / _visual.scale))


func height_at(world_feet: Vector2) -> float:
	return float(_platform.call("height_at", world_feet)) if _platform != null else 0.0


func _physics_process(_delta: float) -> void:
	var inside: bool = is_instance_valid(actor) and supports_feet(actor.to_global(VISUAL.FEET_OFFSET))
	var available: bool = inside and can_travel()
	var interact: bool = bool(data.get("Interact", false))
	_action.call("set_available", available and interact)
	_visual.call("set_active", available and bool(data.get("ShowActivation", false)))
	if not is_instance_valid(actor): return
	if not inside:
		_armed = true
		return
	if _armed and not interact and available:
		_armed = false
		travel_requested.emit(self)


func condition_satisfied() -> bool:
	var requirement: String = str(data.get("RequiredCondition", ""))
	return requirement.is_empty() or (is_instance_valid(gameplay) and bool(gameplay.call("is_condition_met", requirement)))


func can_travel() -> bool:
	if not is_instance_valid(actor) or actor.intro_locked or actor.dead or not condition_satisfied():
		return false
	if travel_available.is_valid():
		return bool(travel_available.call())
	return not str(data.get("TargetLevel", "")).is_empty() or not str(data.get("TargetScene", "")).is_empty()


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
		_visual.call("set_active", false)
		get_viewport().set_input_as_handled()
		travel_requested.emit(self)
