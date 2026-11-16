extends RefCounted
## A single attacker per pack. Damage forces a retreat and immediate hand-off.
enum State { ORBIT, RETREAT }
var state: State = State.ORBIT
var retreat_left: float = 0.0
var retreat_goal: Vector2 = Vector2.ZERO


func tick(actor: InsectActor, delta: float) -> void:
	if state == State.RETREAT:
		retreat_left = maxf(retreat_left - delta, 0.0)
		actor.drive_to(retreat_goal, 1.12)
		if retreat_left <= 0.0: state = State.ORBIT
		return
	if actor.attack_in_progress():
		if actor.attack_is_active(): actor.drive_direction(actor.attack_direction, actor.profile.lunge_speed)
		else: actor.stop_motion()
		return
	if actor.owns_fly_turn():
		actor.approach_player()
		if actor.can_start_attack(): actor.begin_attack()
	else:
		var away: Vector2 = actor.player.global_position.direction_to(actor.global_position)
		if away.is_zero_approx(): away = Vector2.from_angle(actor.phase)
		var orbit: Vector2 = away.rotated(0.30 * actor.orbit_sign)
		actor.drive_to(actor.player.global_position + orbit * (58.0 + fmod(actor.phase, 3.0) * 4.0))


func can_take_turn() -> bool:
	return state == State.ORBIT


func on_damaged(actor: InsectActor) -> void:
	_withdraw(actor, &"damaged")


func on_attack_finished(actor: InsectActor) -> void:
	_withdraw(actor, &"attack_finished")


func _withdraw(actor: InsectActor, reason: StringName) -> void:
	actor.cancel_attack()
	state = State.RETREAT
	retreat_left = actor.profile.retreat_duration
	var away: Vector2 = actor.player.global_position.direction_to(actor.global_position)
	if away.is_zero_approx(): away = -actor.attack_direction
	retreat_goal = actor.global_position + away * actor.profile.retreat_distance
	actor.squad.call("yield_fly_turn", actor, reason)


func reset(actor: InsectActor) -> void:
	state = State.ORBIT
	retreat_left = 0.0
	actor.cancel_attack()
