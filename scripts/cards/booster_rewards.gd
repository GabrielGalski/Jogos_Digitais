extends Node
## Collection for this play session, shared by the maps and retry scenes.

var _counts: Dictionary[StringName, int] = {}


func grant(cards: Array[CardDefinition]) -> void:
	for card: CardDefinition in cards:
		_counts[card.card_id] = count(card.card_id) + 1


func count(card_id: StringName) -> int:
	return _counts.get(card_id, 0)
