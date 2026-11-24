extends Node2D
## Shared stone opener and pack viewer for encounter rewards.

signal reward_claimed

const VIEWER: PackedScene = preload("res://scenes/cards/booster_viewer.tscn")
const WORLD_BODY_WIDTH: float = 39.375

var player: Player
var _opener: Node2D
var _reward_volume: int = 0
var _reward_cards: Array[CardDefinition] = []
var _opening_layer: CanvasLayer
var _previous_pause: bool = false


func _configure_opener(model: PackedScene, anchor: Vector2, terrain_height: float) -> void:
	position = anchor
	_opener = model.instantiate() as Node2D
	_opener.name = "BoosterOpener"
	_set_reward_available(false)
	_opener.set("click_interaction_enabled", true)
	add_child(_opener)
	_opener.connect("interacted", _show_reward)
	_opener.call("fit_on_platform", WORLD_BODY_WIDTH / absf(global_scale.x), Vector2.ZERO, terrain_height)


func _bind_player(subject: Player) -> void:
	player = subject
	_opener.call("bind_player", player)


func _set_reward_available(available: bool) -> void:
	_opener.set("interaction_enabled", available)
	_opener.set("action_prompt_enabled", available)


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
	viewer.booster_opened.connect(_claim_reward, CONNECT_ONE_SHOT)
	viewer.viewer_closed.connect(_opening_layer.queue_free, CONNECT_ONE_SHOT)
	tree.paused = true
	viewer.open_pack(_reward_volume, _reward_cards)


func _claim_reward(cards: Array[CardDefinition]) -> void:
	if _reward_volume == 0:
		return
	get_node("/root/BoosterRewards").call("grant", cards)
	_reward_volume = 0
	_reward_cards.clear()
	_set_reward_available(false)
	reward_claimed.emit()


func _restore_pause() -> void:
	get_tree().paused = _previous_pause
