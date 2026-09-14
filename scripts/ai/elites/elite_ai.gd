class_name EliteAI
extends EnemyAIBase

@export var elite_profile: EliteAIProfile

var special_cooldown_remaining: float = 0.0


func _ready() -> void:
	if elite_profile == null:
		elite_profile = EliteAIProfile.new()
	profile = elite_profile
	super._ready()


func evaluate(observation: EnemyAIObservation, delta: float) -> EnemyAIDecision:
	special_cooldown_remaining = maxf(special_cooldown_remaining - maxf(delta, 0.0), 0.0)
	return super.evaluate(observation, delta)


func notify_special_attack_committed(duration: float = -1.0) -> void:
	var cooldown: float = elite_profile.special_cooldown if duration < 0.0 else duration
	special_cooldown_remaining = maxf(cooldown, 0.0)
	reset_decision_timer()


func _evaluate_observation(observation: EnemyAIObservation) -> EnemyAIDecision:
	if observation.objective != EnemyAIEnums.Objective.PRESSURE_TARGET:
		return super._evaluate_observation(observation)
	if not observation.chamber_active or not observation.target_valid or not observation.target_reachable:
		return super._evaluate_observation(observation)
	if attack_cooldown_remaining > 0.0:
		return _recovery_decision(observation)

	if _can_use_special(observation):
		return _special_attack_decision(observation)

	var close_slot: EnemyAISlot = observation.available_slot(EnemyAIEnums.Role.ELITE)
	if close_slot != null and observation.line_of_sight_clear and observation.distance_to_target <= profile.attack_range + close_slot.radius:
		return _close_attack_decision(observation, close_slot)
	if close_slot != null:
		return _approach_slot_decision(observation, close_slot)
	return _orbit_decision(observation, "elite_space_is_occupied")


func influence_radius() -> float:
	return elite_profile.influence_radius


func max_influenced_minions() -> int:
	return elite_profile.max_influenced_minions


func _can_use_special(observation: EnemyAIObservation) -> bool:
	return (
		special_cooldown_remaining <= 0.0
		and not elite_profile.special_attack_id.is_empty()
		and observation.target_visible
		and observation.distance_to_target >= elite_profile.special_min_distance
		and observation.landing_position_valid
	)


func _special_attack_decision(observation: EnemyAIObservation) -> EnemyAIDecision:
	var decision: EnemyAIDecision = EnemyAIDecision.new(EnemyAIEnums.Intent.PREPARE)
	decision.attack_id = elite_profile.special_attack_id
	decision.target_position = observation.target_position
	decision.desired_position = observation.target_position
	decision.movement_direction = Vector2.ZERO
	decision.lock_movement = true
	decision.reason = &"special_attack_range_and_landing_valid"
	return decision


func _close_attack_decision(observation: EnemyAIObservation, slot: EnemyAISlot) -> EnemyAIDecision:
	var decision: EnemyAIDecision = EnemyAIDecision.new(EnemyAIEnums.Intent.PREPARE)
	decision.attack_id = elite_profile.close_attack_id
	decision.target_position = observation.target_position
	decision.desired_position = slot.position
	decision.reserve_slot_id = slot.slot_id
	decision.movement_direction = _separation_direction(observation)
	decision.lock_movement = true
	decision.reason = &"elite_close_slot_available"
	return decision


func _approach_slot_decision(observation: EnemyAIObservation, slot: EnemyAISlot) -> EnemyAIDecision:
	var primary_direction: Vector2 = _direction_to_position(observation.self_position, slot.position)
	var decision: EnemyAIDecision = _movement_decision(
		EnemyAIEnums.Intent.APPROACH,
		_safe_route_direction(observation, primary_direction),
		slot.position,
		"elite_approach_close_slot",
		_separation_direction(observation)
	)
	decision.reserve_slot_id = slot.slot_id
	return decision


func _orbit_decision(observation: EnemyAIObservation, reason: String) -> EnemyAIDecision:
	var to_target: Vector2 = _direction_to_target(observation)
	var tangent: Vector2 = Vector2(-to_target.y, to_target.x)
	if tangent.length_squared() <= 0.0001:
		tangent = Vector2.RIGHT
	var decision: EnemyAIDecision = EnemyAIDecision.new(EnemyAIEnums.Intent.ORBIT)
	decision.movement_direction = _combine_direction(tangent, _separation_direction(observation))
	decision.desired_position = observation.target_position + tangent * profile.preferred_distance
	decision.target_position = observation.target_position
	decision.reason = StringName(reason)
	return decision


func _recovery_decision(observation: EnemyAIObservation) -> EnemyAIDecision:
	var separation: Vector2 = _separation_direction(observation)
	var decision: EnemyAIDecision = EnemyAIDecision.new(EnemyAIEnums.Intent.RECOVER)
	decision.movement_direction = separation
	decision.desired_position = observation.self_position + separation * profile.personal_space
	decision.reason = &"elite_attack_cooldown"
	return decision