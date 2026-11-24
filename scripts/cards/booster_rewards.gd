extends Node
## Collection for this play session, shared by the maps and retry scenes.

const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const VIEWER: PackedScene = preload("res://scenes/cards/booster_viewer.tscn")

var _counts: Dictionary[StringName, int] = {}
var _pending: Array[Dictionary] = []


func queue_random_pack() -> void:
	var volume: int = randi_range(1, CATALOG.PACK_CODES.size())
	_pending.append({"volume": volume, "cards": CATALOG.draw_pack(volume)})


func pending_count() -> int:
	return _pending.size()


func open_pending(player: Player) -> bool:
	var tree: SceneTree = get_tree()
	if _pending.is_empty() or tree.current_scene == null or tree.paused or player.dead or player.intro_locked:
		return false
	if tree.get_first_node_in_group(&"card_table_modal") != null:
		return false
	var driver: Node = player.get_node_or_null("GameplayKit/Manifestations")
	if driver != null:
		driver.call("suspend_trigger")
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "DragonGreedPack"
	layer.layer = 100
	layer.add_to_group(&"card_table_modal")
	layer.tree_exiting.connect(func() -> void: tree.paused = false, CONNECT_ONE_SHOT)
	tree.current_scene.add_child(layer)
	var viewer: BoosterViewer = VIEWER.instantiate() as BoosterViewer
	layer.add_child(viewer)
	viewer.viewer_closed.connect(layer.queue_free, CONNECT_ONE_SHOT)
	viewer.booster_opened.connect(_claim_pending, CONNECT_ONE_SHOT)
	var pack: Dictionary = _pending.front()
	tree.paused = true
	viewer.open_pack(int(pack.volume), pack.cards as Array[CardDefinition])
	return true


func _claim_pending(cards: Array[CardDefinition]) -> void:
	_pending.pop_front()
	grant(cards)


func grant(cards: Array[CardDefinition]) -> void:
	for card: CardDefinition in cards:
		_counts[card.card_id] = count(card.card_id) + 1


func count(card_id: StringName) -> int:
	return _counts.get(card_id, 0)
