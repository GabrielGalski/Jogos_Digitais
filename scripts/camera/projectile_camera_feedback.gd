extends RefCounted
## Bounded shot/impact envelopes; owns no camera, physics, damage or global timescale.

var profile: Resource = null
var shot_direction: Vector2 = Vector2.ZERO
var shot_remaining: float = 0.0
var impact_direction: Vector2 = Vector2.ZERO
var impact_remaining: float = 0.0
var impact_duration: float = 0.0
var impact_strength: float = 0.0
var impact_shake: float = 0.0


func shot(direction: Vector2) -> void:
	shot_direction = -direction.normalized()
	shot_remaining = float(profile.get("shot_duration"))


func hit(direction: Vector2, killed: bool) -> void:
	_push_impact(direction, float(profile.get("kill_kick" if killed else "hit_kick")),
		float(profile.get("kill_duration" if killed else "hit_duration")),
		float(profile.get("kill_shake" if killed else "hit_shake")))


func wall(direction: Vector2) -> void:
	_push_impact(direction, float(profile.get("wall_kick")), float(profile.get("wall_duration")), 0.0)


func _push_impact(direction: Vector2, strength: float, duration: float, shake: float) -> void:
	# Collateral kills/ticks in the same frame do not stack or prolong a weak pulse.
	var current: float = impact_strength * pow(impact_remaining / maxf(impact_duration, 0.001), 2.0)
	if strength < current:
		return
	impact_direction = direction.normalized()
	impact_strength = strength
	impact_duration = maxf(duration, 0.001)
	impact_remaining = impact_duration
	impact_shake = shake


func advance(delta: float) -> Vector2:
	shot_remaining = maxf(shot_remaining - delta, 0.0)
	impact_remaining = maxf(impact_remaining - delta, 0.0)
	var shot_fade: float = pow(shot_remaining / maxf(float(profile.get("shot_duration")), 0.001), 2.0)
	var impact_fade: float = pow(impact_remaining / maxf(impact_duration, 0.001), 2.0)
	var progress: float = 1.0 - impact_remaining / maxf(impact_duration, 0.001)
	var recoil: Vector2 = shot_direction * float(profile.get("shot_kick")) * shot_fade
	var hit_offset: Vector2 = impact_direction * impact_strength * impact_fade
	var shake: Vector2 = impact_direction.orthogonal() * sin(progress * TAU * 3.0) * impact_shake * impact_fade
	return (recoil + hit_offset + shake).limit_length(float(profile.get("maximum_offset")))


func reset() -> void:
	shot_remaining = 0.0
	impact_remaining = 0.0
