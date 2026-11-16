extends RefCounted
## Independent hit-and-run. Rounded weaving follows A*; cover is never a stop order.
enum State { APPROACH, RETREAT, CIRCLE }
var state: State = State.APPROACH
var remaining: float = 0.0
var cover: Node2D = null
var fallback: Vector2 = Vector2.ZERO
var _clock: float = 0.0


func tick(actor: InsectActor, delta: float) -> void:
	_clock += delta
	if actor.attack_in_progress():
		if actor.attack_is_active(): actor.drive_direction(actor.attack_direction, actor.profile.lunge_speed)
		else:
			# Keep the telegraph/recovery readable while sidestepping instead of freezing.
			var side: Vector2 = actor.attack_direction.orthogonal() * actor.orbit_sign
			actor.drive_to(actor.global_position + side * 24.0, 0.55, _curve(actor))
		return
	if state == State.RETREAT:
		remaining -= delta
		var goal: Vector2 = _cover_goal(actor)
		actor.drive_to(goal, 1.25, _curve(actor))
		if remaining <= 0.0 or actor.global_position.distance_to(goal) < 18.0:
			state = State.CIRCLE
			remaining = 0.55 + fmod(actor.phase, 0.45)
			_circle(actor)
	elif state == State.CIRCLE:
		remaining -= delta
		_circle(actor)
		if remaining <= 0.0: state = State.APPROACH
	else:
		var away: Vector2 = actor.player.global_position.direction_to(actor.global_position)
		actor.drive_to(actor.player.global_position + away * (actor.profile.body_radius + 6.0), 1.0, _curve(actor))
		if actor.can_start_attack(): actor.begin_attack()


func _curve(actor: InsectActor) -> float:
	# 16-degree sinusoidal steering, with a 1.45-1.70s period and independent phase.
	return sin(_clock * (3.7 + fmod(actor.phase, 0.65)) + actor.phase) * 0.28


func _circle(actor: InsectActor) -> void:
	var away: Vector2 = actor.player.global_position.direction_to(actor.global_position)
	if away.is_zero_approx(): away = -actor.attack_direction
	var tangent: Vector2 = away.orthogonal() * actor.orbit_sign
	var cover_distance: float = maxf(_cover_goal(actor).distance_to(actor.player.global_position), 44.0)
	var correction: float = clampf((cover_distance - actor.player_distance()) / 28.0, -0.6, 0.8)
	# A moving look-ahead point prevents arrival braking behind another enemy.
	var direction: Vector2 = (tangent + away * correction).normalized()
	actor.drive_to(actor.global_position + direction * 32.0, 0.85, _curve(actor) * 0.65)


func on_attack_finished(actor: InsectActor) -> void:
	_retreat(actor)


func on_damaged(actor: InsectActor) -> void:
	actor.cancel_attack()
	_retreat(actor)


func _retreat(actor: InsectActor) -> void:
	state = State.RETREAT
	remaining = actor.profile.retreat_duration
	var away: Vector2 = actor.player.global_position.direction_to(actor.global_position)
	if away.is_zero_approx(): away = -actor.attack_direction
	fallback = actor.global_position + away * actor.profile.retreat_distance
	cover = null
	var best: float = INF
	for candidate: Node2D in actor.neighbors:
		if not is_instance_valid(candidate) or candidate == actor or not candidate.has_method("is_alive") or not bool(candidate.call("is_alive")): continue
		var radial: Vector2 = actor.player.global_position.direction_to(candidate.global_position)
		# Cover must lie on this side of Nox; never flee through the player's feet.
		if radial.dot(away) < 0.35: continue
		var goal: Vector2 = candidate.global_position + radial * 24.0
		if goal.distance_to(actor.player.global_position) < actor.player_distance() + 16.0: continue
		var distance: float = actor.global_position.distance_squared_to(goal)
		if distance < best and distance < 144.0 * 144.0:
			best = distance
			cover = candidate


func _cover_goal(actor: InsectActor) -> Vector2:
	if is_instance_valid(cover) and cover.has_method("is_alive") and bool(cover.call("is_alive")):
		return cover.global_position + actor.player.global_position.direction_to(cover.global_position) * 24.0
	return fallback


func reset(actor: InsectActor) -> void:
	state = State.APPROACH
	cover = null
	remaining = 0.0
	actor.cancel_attack()
