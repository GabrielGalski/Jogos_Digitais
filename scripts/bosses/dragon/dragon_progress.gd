extends Node
## World boss state lasts across scene changes and retries in this play session.

signal rewards_changed

const RESPAWN_MSEC: int = 20 * 60 * 1000
const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")

var respawn_at_msec: int = 0
var _pending_rewards: Array[Dictionary] = []


func can_spawn() -> bool:
	return Time.get_ticks_msec() >= respawn_at_msec


func record_defeat() -> void:
	if not can_spawn():
		return
	respawn_at_msec = Time.get_ticks_msec() + RESPAWN_MSEC
	var volume: int = CATALOG.DRAGON_PACK
	_pending_rewards.append({"volume": volume, "cards": CATALOG.draw_pack(volume)})
	rewards_changed.emit()


func pending_reward() -> Dictionary:
	return _pending_rewards.front() if not _pending_rewards.is_empty() else {}


func claim_reward() -> void:
	if not _pending_rewards.is_empty():
		_pending_rewards.pop_front()
		rewards_changed.emit()
