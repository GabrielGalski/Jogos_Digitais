extends Node2D
## The authored totem follows its encounter; the encounter owns all combat rules.

const OPENER: PackedScene = preload("res://scenes/structures/booster_opener_marked.tscn")
const MARKER: Script = preload("res://scripts/visual/booster_exclamation.gd")
const ACTION_PROMPT: Script = preload("res://scripts/visual/world_action_prompt.gd")
const HORDE: Script = preload("res://scripts/dungeon/spirit_horde_encounter.gd")

var player: Player
var encounter: Node2D
var progress: float:
	get:
		if not is_instance_valid(encounter):
			return 0.0
		return clampf(float(encounter.get("defeated_count")) / maxf(1.0, float(encounter.get("kill_target"))), 0.0, 1.0)
var data: Dictionary
var _opener: Node2D
var _idle_marker: Node2D
var _warning: Node2D
var _action: Sprite2D


func configure(description: Dictionary) -> void:
	data = description
	position = data["position"]
	_opener = OPENER.instantiate() as Node2D
	_opener.name = "BoosterOpener"
	_opener.set("action_prompt_enabled", false)
	add_child(_opener)
	var terrain_height: float = float(data.get("TerrainHeight", 0.0))
	var width: float = float(data.get("BodyWidth", 63.36))
	_opener.call("fit_on_platform", width / absf(global_scale.x), Vector2.ZERO, terrain_height)
	_idle_marker = _opener.get_node("Visuals/ExclamationMarker") as Node2D
	_warning = MARKER.new() as Node2D
	_warning.name = "CombatWarning"
	_warning.set("combat_warning", true)
	_opener.get_node("Visuals").add_child(_warning)
	_warning.call("set_active", false)
	_action = ACTION_PROMPT.new() as Sprite2D
	_action.name = "ActionPrompt"
	add_child(_action)
	_action.scale = Vector2.ONE / global_scale.abs()
	_action.call("configure", Vector2(0, -terrain_height - MARKER.HEIGHT_ABOVE_BODY) / global_scale.abs())


func bind_encounter(subject: Player, horde: Node2D) -> void:
	player = subject
	encounter = horde
	_opener.call("bind_player", player)
	encounter.connect("started", _refresh)
	encounter.connect("cleared", _refresh)
	encounter.connect("aborted", _refresh)
	_refresh()


func can_activate() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(encounter):
		return false
	return int(encounter.get("phase")) == HORDE.Phase.WAITING and not player.dead \
		and not player.intro_locked and not player.is_dashing() \
		and player.global_position.distance_to(global_position) <= float(_opener.get("activation_radius")) \
		and bool(encounter.call("can_begin"))


func _refresh() -> void:
	var phase: int = int(encounter.get("phase"))
	var available: bool = can_activate()
	_idle_marker.call("set_active", phase == HORDE.Phase.WAITING and not available)
	_action.call("set_available", available)
	_warning.call("set_active", phase == HORDE.Phase.ACTIVE)
	_opener.set("interaction_enabled", phase == HORDE.Phase.CLEARED)
	set_physics_process(phase == HORDE.Phase.WAITING)


func _physics_process(_delta: float) -> void:
	if is_instance_valid(encounter):
		_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or (key.physical_keycode != KEY_E and key.keycode != KEY_E):
		return
	if can_activate():
		get_viewport().set_input_as_handled()
		encounter.call("begin")
