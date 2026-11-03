extends RefCounted
## Shared identity for perception and damage; legacy enemies use their groups.

const MONSTERS: StringName = &"monsters"
const PLAYER: StringName = &"player"
const NEUTRAL: StringName = &"neutral"


static func faction_of(actor: Node) -> StringName:
	if not is_instance_valid(actor): return NEUTRAL
	if actor.has_method("get_combat_faction"):
		return StringName(str(actor.call("get_combat_faction")))
	if actor is Player: return PLAYER
	if actor.is_in_group(&"enemy_bodies") or actor.is_in_group(&"enemy_ai_actor"): return MONSTERS
	return NEUTRAL


static func are_allies(first: Node, second: Node) -> bool:
	var faction: StringName = faction_of(first)
	return faction != NEUTRAL and faction == faction_of(second)


static func can_damage(source_faction: StringName, target: Node) -> bool:
	var target_faction: StringName = faction_of(target)
	return source_faction != NEUTRAL and target_faction != NEUTRAL and source_faction != target_faction
