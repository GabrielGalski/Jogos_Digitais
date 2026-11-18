extends Node2D
## The authored totem follows its encounter; the encounter owns all combat rules.

const OPENER: PackedScene = preload("res://scenes/structures/booster_opener_marked.tscn")
const MARKER: Script = preload("res://scripts/visual/booster_exclamation.gd")
const ACTION_PROMPT: Script = preload("res://scripts/visual/world_action_prompt.gd")
const HORDE: Script = preload("res://scripts/dungeon/spirit_horde_encounter.gd")
const VIEWER: PackedScene = preload("res://scenes/cards/booster_viewer.tscn")
const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")

var player: Player
var encounter: Node2D
var progress: float:
	get:
		if not is_instance_valid(encounter):
			return 0.0
		return float(encounter.call("completion_progress"))
var data: Dictionary
var _opener: Node2D
var _idle_marker: Node2D
var _warning: Node2D
var _action: Sprite2D
var _reward_issued: bool = false
var _reward_volume: int = 0
var _reward_cards: Array[CardDefinition] = []
var _opening_layer: CanvasLayer
var _previous_pause: bool = false


func configure(description: Dictionary) -> void:
	data = description
	position = data["position"]
	_opener = OPENER.instantiate() as Node2D
	_opener.name = "BoosterOpener"
	_opener.set("action_prompt_enabled", false)
	_opener.set("click_interaction_enabled", true)
	add_child(_opener)
	_opener.connect("interacted", _show_reward)
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
	_warning.call("set_active", phase == HORDE.Phase.ACTIVE)
	var reward_available: bool = phase == HORDE.Phase.CLEARED and _reward_volume > 0
	_opener.set("interaction_enabled", reward_available)
	_opener.set("action_prompt_enabled", reward_available)
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
		_reward_volume = randi_range(1, BoosterViewer.PACKS.size())
		var pool: Array[CardDefinition] = CATALOG.implemented_cards()
		pool.shuffle()
		_reward_cards.assign(pool.slice(0, mini(3, pool.size())))
	_refresh()


func _show_reward() -> void:
	var tree: SceneTree = get_tree()
	if (
		_reward_volume == 0 or _reward_cards.is_empty() or is_instance_valid(_opening_layer)
		or tree.paused or tree.get_first_node_in_group(&"card_table_modal") != null
		or not is_instance_valid(player) or player.dead or player.intro_locked
	):
		return
	var driver: Node = player.get_node_or_null("GameplayKit/Manifestations")
	if driver != null:
		driver.call("suspend_trigger")
	_previous_pause = tree.paused
	_opening_layer = CanvasLayer.new()
	_opening_layer.name = "PackOpening"
	_opening_layer.layer = 100
	_opening_layer.add_to_group(&"card_table_modal")
	_opening_layer.tree_exiting.connect(_restore_pause, CONNECT_ONE_SHOT)
	add_child(_opening_layer)
	var viewer: BoosterViewer = VIEWER.instantiate() as BoosterViewer
	_opening_layer.add_child(viewer)
	viewer.booster_opened.connect(_claim_reward)
	viewer.viewer_closed.connect(_close_reward)
	tree.paused = true
	viewer.open_pack(_reward_volume, _reward_cards)


func _claim_reward(cards: Array[CardDefinition]) -> void:
	if _reward_volume == 0:
		return
	get_node("/root/BoosterRewards").call("grant", cards)
	_reward_volume = 0
	_reward_cards.clear()
	_refresh()


func _close_reward() -> void:
	if not is_instance_valid(_opening_layer):
		return
	_opening_layer.queue_free()


func _restore_pause() -> void:
	get_tree().paused = _previous_pause
