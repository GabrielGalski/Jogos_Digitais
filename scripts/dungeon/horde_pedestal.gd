extends "res://scripts/structures/booster_reward_pedestal.gd"
## The authored totem follows its encounter; the encounter owns all combat rules.

const OPENER: PackedScene = preload("res://scenes/structures/booster_opener_marked.tscn")
const MARKER: Script = preload("res://scripts/visual/booster_exclamation.gd")
const ACTION_PROMPT: Script = preload("res://scripts/visual/world_action_prompt.gd")
const HORDE: Script = preload("res://scripts/dungeon/spirit_horde_encounter.gd")
const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")

var encounter: Node2D
var progress: float:
	get:
		if not is_instance_valid(encounter):
			return 0.0
		return float(encounter.call("completion_progress"))
var data: Dictionary
var _idle_marker: Node2D
var _warning: Node2D
var _action: Sprite2D
var _reward_issued: bool = false


func configure(description: Dictionary) -> void:
	data = description
	_configure_opener(OPENER, data["position"], float(data.get("TerrainHeight", 0.0)))
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
	_action.call("configure", to_local(_idle_marker.call("prompt_world_position")))


func bind_encounter(subject: Player, horde: Node2D) -> void:
	_bind_player(subject)
	encounter = horde
	encounter.connect("started", _on_encounter_started)
	encounter.connect("cleared", _on_encounter_cleared)
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
	var active: bool = phase == HORDE.Phase.ACTIVE
	_warning.call("set_active", active)
	_opener.call("set_horde_active", active)
	var reward_available: bool = phase == HORDE.Phase.CLEARED and _reward_volume > 0
	_set_reward_available(reward_available)
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


func _on_encounter_started() -> void:
	_reward_issued = false
	_refresh()


func _on_encounter_cleared() -> void:
	if not _reward_issued:
		_reward_issued = true
		_reward_volume = randi_range(1, CATALOG.DRAGON_PACK - 1)
		_reward_cards = CATALOG.draw_horde_pack(_reward_volume)
	_refresh()
