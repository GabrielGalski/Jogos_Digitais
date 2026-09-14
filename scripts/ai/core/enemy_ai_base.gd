class_name EnemyAIBase
extends Node

signal decision_produced(decision: EnemyAIDecision)

@export var profile: EnemyAIProfile
@export var enabled: bool = true

var current_intent: int = EnemyAIEnums.Intent.IDLE
var attack_cooldown_remaining: float = 0.0

var _decision_time_remaining: float = 0.0
var _last_decision: EnemyAIDecision = null


func _ready() -> void:
	if profile == null:
		profile = EnemyAIProfile.new()


func evaluate(observation: EnemyAIObservation, delta: float) -> EnemyAIDecision:
	if not enabled or observation == null or not observation.chamber_active or observation.objective == EnemyAIEnums.Objective.DISABLED:
		reset_decision_timer()
		current_intent = EnemyAIEnums.Intent.DISABLED
		return _disabled_decision("disabled_or_inactive")
	var safe_delta: float = maxf(delta, 0.0)
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - safe_delta, 0.0)
	_decision_time_remaining = maxf(_decision_time_remaining - safe_delta, 0.0)
	if _decision_time_remaining > 0.0 and _last_decision != null:
		return _last_decision
	_decision_time_remaining = maxf(profile.think_interval, 0.01)

	var decision: EnemyAIDecision
	if not enabled or observation == null:
		decision = _disabled_decision("disabled_or_missing_observation")
	else:
		observation.refresh_distance()
		decision = _evaluate_observation(observation)
	_last_decision = decision
	current_intent = decision.intent
	decision_produced.emit(decision)
	return decision


func notify_attack_committed(duration: float = -1.0) -> void:
	var cooldown: float = profile.attack_cooldown if duration < 0.0 else duration
	attack_cooldown_remaining = maxf(cooldown, 0.0)
	reset_decision_timer()


func reset_decision_timer() -> void:
	_decision_time_remaining = 0.0
	_last_decision = null


func _evaluate_observation(observation: EnemyAIObservation) -> EnemyAIDecision:
	var separation: Vector2 = _separation_direction(observation)
	if observation.objective == EnemyAIEnums.Objective.DISABLED or not observation.chamber_active:
		return _disabled_decision("chamber_inactive")
	if observation.objective == EnemyAIEnums.Objective.RETREAT:
		return _movement_decision(
			EnemyAIEnums.Intent.RETREAT,
			_safe_route_direction(observation, -_direction_to_target(observation)),
			observation.nearest_fallback(),
			"retreat_objective",
			separation
		)
	if observation.objective == EnemyAIEnums.Objective.DEFEND_POSITION and observation.has_objective_position:
		var defend_direction: Vector2 = _direction_to_position(observation.self_position, observation.objective_position)
		if defend_direction.length_squared() > 0.01:
			return _movement_decision(
				EnemyAIEnums.Intent.APPROACH,
				_safe_route_direction(observation, defend_direction),
				observation.objective_position,
				"return_to_defend_position",
				separation
			)
		return _movement_decision(EnemyAIEnums.Intent.HOLD, separation, observation.self_position, "defend_position", separation)
	if observation.objective == EnemyAIEnums.Objective.IDLE:
		return _movement_decision(EnemyAIEnums.Intent.HOLD, separation, observation.self_position, "idle_objective", separation)
	if not observation.target_valid or not observation.target_reachable:
		return _movement_decision(
			EnemyAIEnums.Intent.REPOSITION,
			_safe_route_direction(observation, _direction_to_position(observation.self_position, observation.nearest_fallback())),
			observation.nearest_fallback(),
			"target_not_reachable",
			separation
		)
	if observation.distance_to_target > profile.target_acquisition_radius:
		return _movement_decision(EnemyAIEnums.Intent.HOLD, separation, observation.self_position, "target_outside_acquisition_radius", separation)
	return _movement_decision(
		EnemyAIEnums.Intent.APPROACH,
		_safe_route_direction(observation, _direction_to_target(observation)),
		observation.target_position,
		"base_pressure_approach",
		separation
	)


func _movement_decision(
		intent: int,
		primary_direction: Vector2,
		desired_position: Vector2,
		reason: String,
		separation: Vector2 = Vector2.ZERO
	) -> EnemyAIDecision:
	var decision: EnemyAIDecision = EnemyAIDecision.new(intent)
	decision.movement_direction = _combine_direction(primary_direction, separation)
	decision.desired_position = desired_position
	decision.reason = StringName(reason)
	return decision


func _disabled_decision(reason: String) -> EnemyAIDecision:
	var decision: EnemyAIDecision = EnemyAIDecision.new(EnemyAIEnums.Intent.DISABLED)
	decision.reason = StringName(reason)
	decision.lock_movement = true
	return decision


func _separation_direction(observation: EnemyAIObservation) -> Vector2:
	var result: Vector2 = Vector2.ZERO
	var considered: int = 0
	for neighbor: EnemyAINeighbor in observation.neighbors:
		if neighbor == null or neighbor.actor_id == observation.actor_id:
			continue
		considered += 1
		if considered > profile.max_neighbors:
			break
		var offset: Vector2 = observation.self_position - neighbor.position
		var distance: float = offset.length()
		var minimum_distance: float = profile.personal_space + observation.self_radius + neighbor.radius
		if distance > 0.001 and distance < minimum_distance:
			var urgency: float = (minimum_distance - distance) / minimum_distance
			result += offset.normalized() * urgency
	return result.limit_length(1.0)


func _combine_direction(primary: Vector2, separation: Vector2) -> Vector2:
	var combined: Vector2 = primary * profile.movement_weight
	combined += separation.limit_length(0.6 if not primary.is_zero_approx() else 1.0) * profile.separation_weight
	if combined.length_squared() <= 0.0001:
		return Vector2.ZERO
	return combined.normalized()


func _safe_route_direction(observation: EnemyAIObservation, fallback: Vector2) -> Vector2:
	if observation.route_valid and observation.route_direction.length_squared() > 0.0001:
		return observation.route_direction.normalized()
	if not observation.target_reachable:
		return Vector2.ZERO
	return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector2.ZERO


func _direction_to_target(observation: EnemyAIObservation) -> Vector2:
	return _direction_to_position(observation.self_position, observation.target_position)


func _direction_to_position(from_position: Vector2, to_position: Vector2) -> Vector2:
	var offset: Vector2 = to_position - from_position
	return offset.normalized() if offset.length_squared() > 0.0001 else Vector2.ZERO
