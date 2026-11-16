extends RefCounted
## Relentless front line: no retreat and no hit stun; the slow strike is committed.


func tick(actor: InsectActor, _delta: float) -> void:
	actor.approach_player(0.48 if actor.attack_in_progress() else 1.0)
	if not actor.attack_in_progress() and actor.can_start_attack():
		actor.begin_attack()


func on_damaged(_actor: InsectActor) -> void:
	pass


func on_attack_finished(_actor: InsectActor) -> void:
	pass


func reset(_actor: InsectActor) -> void:
	pass
