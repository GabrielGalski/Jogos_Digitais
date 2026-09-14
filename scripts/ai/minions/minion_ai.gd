class_name MinionAI
extends EnemyAIBase

@export var minion_profile: MinionAIProfile


func _ready() -> void:
	if minion_profile == null:
		minion_profile = MinionAIProfile.new()
	profile = minion_profile
	super._ready()


func _evaluate_observation(observation: EnemyAIObservation) -> EnemyAIDecision:
	if observation.objective != EnemyAIEnums.Objective.PRESSURE_TARGET:
		return super._evaluate_observation(observation)
	if not observation.chamber_active or not observation.target_valid or not observation.target_reachable:
		return super._evaluate_observation(observation)
	if attack_cooldown_remaining > 0.0:
		return _recovery_decision(observation)

	var slot: EnemyAISlot = observation.available_slot(minion_profile.role) if minion_profile.use_attack_slots else null
	if minion_profile.role == EnemyAIEnums.Role.RANGED:
		return _evaluate_ranged(observation, slot)
	return _evaluate_close_range(observation, slot)


func _evaluate_close_range(observation: EnemyAIObservation, slot: EnemyAISlot) -> EnemyAIDecision:
	if slot != null and observation.line_of_sight_clear and observation.distance_to_target <= profile.attack_range + slot.radius:
		return _attack_decision(observation, slot)
	if slot != null:
		return _approach_slot_decision(observation, slot)
	return _orbit_decision(observation, "no_close_range_slot")


func _evaluate_ranged(observation: EnemyAIObservation, slot: EnemyAISlot) -> EnemyAIDecision:
	if observation.distance_to_target < profile.preferred_distance:
		var retreat_direction: Vector2 = _direction_to_target(observation) * -1.0
		return _movement_decision(
			EnemyAIEnums.Intent.RETREAT,
			_safe_route_direction(observation, retreat_direction),
			observation.nearest_fallback(),
			"ranged_preferred_distance",
			_separation_direction(observation)
		)
	if slot != null and observation.distance_to_target <= profile.attack_range and observation.line_of_sight_clear:
		return _attack_decision(observation, slot)
	if slot != null:
		return _approach_slot_decision(observation, slot)
	return _orbit_decision(observation, "no_ranged_slot")


func _attack_decision(observation: EnemyAIObservation, slot: EnemyAISlot) -> EnemyAIDecision:
	var decision: EnemyAIDecision = EnemyAIDecision.new(EnemyAIEnums.Intent.PREPARE)
	decision.desired_position = slot.position
	decision.target_position = observation.target_position
	decision.attack_id = _chosen_attack_id()
	decision.reserve_slot_id = slot.slot_id
	decision.lock_movement = not _may_attack_while_moving()
	decision.movement_direction = _separation_direction(observation)
	decision.reason = &"attack_slot_available"
	return decision


func _approach_slot_decision(observation: EnemyAIObservation, slot: EnemyAISlot) -> EnemyAIDecision:
	var primary_direction: Vector2 = _direction_to_position(observation.self_position, slot.position)
	var decision: EnemyAIDecision = _movement_decision(
		EnemyAIEnums.Intent.APPROACH,
		_safe_route_direction(observation, primary_direction),
		slot.position,
		"approach_attack_slot",
		_separation_direction(observation)
	)
	decision.reserve_slot_id = slot.slot_id
	return decision


func _orbit_decision(observation: EnemyAIObservation, reason: String) -> EnemyAIDecision:
	var to_target: Vector2 = _direction_to_target(observation)
	var tangent: Vector2 = Vector2(-to_target.y, to_target.x)
	if tangent.length_squared() <= 0.0001:
		tangent = Vector2.RIGHT
	var direction: Vector2 = _combine_direction(tangent, _separation_direction(observation))
	var decision: EnemyAIDecision = EnemyAIDecision.new(EnemyAIEnums.Intent.ORBIT)
	decision.movement_direction = direction
	decision.desired_position = observation.target_position + tangent * minion_profile.preferred_orbit_distance
	decision.target_position = observation.target_position
	decision.reason = StringName(reason)
	return decision


func _recovery_decision(observation: EnemyAIObservation) -> EnemyAIDecision:
	var separation: Vector2 = _separation_direction(observation)
	var intent: int = EnemyAIEnums.Intent.RECOVER
	var direction: Vector2 = separation
	if minion_profile.role == EnemyAIEnums.Role.RANGED and observation.target_valid:
		direction = _combine_direction(-_direction_to_target(observation), separation)
	var decision: EnemyAIDecision = EnemyAIDecision.new(intent)
	decision.movement_direction = direction
	decision.desired_position = observation.self_position + direction * profile.personal_space
	decision.reason = &"attack_cooldown"
	return decision


func _chosen_attack_id() -> StringName:
	return minion_profile.attack_id


func _may_attack_while_moving() -> bool:
	return minion_profile.can_attack_while_moving
