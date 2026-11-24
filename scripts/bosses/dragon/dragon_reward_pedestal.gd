extends "res://scripts/structures/booster_reward_pedestal.gd"
## Offers the dragon's pending booster at the same landmark on each visit.

const OPENER: PackedScene = preload("res://scenes/structures/booster_opener.tscn")

var _progress: Node
var _dragon: Node


func configure(subject: Player, dragon: Node, anchor: Vector2, terrain_height: float) -> void:
	_dragon = dragon
	_configure_opener(OPENER, anchor, terrain_height)
	_bind_player(subject)
	_progress = get_node("/root/DragonProgress")
	_progress.connect("rewards_changed", _sync_reward)
	_dragon.connect("combat_changed", _sync_reward)
	reward_claimed.connect(_on_reward_claimed)
	_sync_reward()


func _sync_reward() -> void:
	var reward: Dictionary = _progress.call("pending_reward")
	_reward_volume = int(reward.get("volume", 0))
	_reward_cards.assign(reward.get("cards", []))
	_set_reward_available(_reward_volume > 0 and not _reward_cards.is_empty() and not bool(_dragon.call("is_fighting")))


func _on_reward_claimed() -> void:
	_progress.call("claim_reward")
