extends Node

var _failures: int = 0


func _ready() -> void:
	var minotaur: MinotaurAI = MinotaurAI.new()
	minotaur._ready()
	var asterion: AsterionAI = AsterionAI.new()
	asterion._ready()

	var close_observation: EnemyAIObservation = _pressure_observation(Vector2(20, 0))
	close_observation.attack_slots.append(EnemyAISlot.new(&"minion_slot", Vector2(16, 0), 10.0))
	var minion_attack: EnemyAIDecision = minotaur.evaluate(close_observation, 0.2)
	_check(minion_attack.intent == EnemyAIEnums.Intent.PREPARE, "minotaur reserves a close attack slot")
	_check(minion_attack.attack_id == &"minotaur_contact", "normal minotaur uses its normal attack")

	minotaur.reset_decision_timer()
	var idle_observation: EnemyAIObservation = _pressure_observation(Vector2(20, 0))
	idle_observation.objective = EnemyAIEnums.Objective.IDLE
	var idle_decision: EnemyAIDecision = minotaur.evaluate(idle_observation, 0.2)
	_check(idle_decision.intent == EnemyAIEnums.Intent.HOLD, "minotaur does not follow an idle objective")

	minotaur.reset_decision_timer()
	minotaur.apply_elite_influence(&"asterion")
	var empowered_observation: EnemyAIObservation = _pressure_observation(Vector2(20, 0))
	empowered_observation.attack_slots.append(EnemyAISlot.new(&"empowered_slot", Vector2(16, 0), 10.0))
	var empowered_attack: EnemyAIDecision = minotaur.evaluate(empowered_observation, 0.2)
	_check(empowered_attack.attack_id == &"walk_attack", "influenced minotaur changes to walk_attack")
	_check(not empowered_attack.lock_movement, "walk_attack keeps movement available")

	var distant_observation: EnemyAIObservation = _pressure_observation(Vector2(200, 0))
	distant_observation.attack_slots.append(EnemyAISlot.new(&"distant_slot", Vector2(160, 0), 10.0))
	minotaur.reset_decision_timer()
	var approach_decision: EnemyAIDecision = minotaur.evaluate(distant_observation, 0.2)
	_check(approach_decision.intent == EnemyAIEnums.Intent.APPROACH, "minotaur approaches a free slot instead of attacking from afar")

	var asterion_observation: EnemyAIObservation = _pressure_observation(Vector2(220, 0))
	asterion_observation.landing_position_valid = true
	asterion.reset_decision_timer()
	var skybreaker_decision: EnemyAIDecision = asterion.evaluate(asterion_observation, 0.2)
	_check(skybreaker_decision.attack_id == &"skybreaker", "Asterion chooses Skybreaker at distance")

	var close_asterion_observation: EnemyAIObservation = _pressure_observation(Vector2(20, 0))
	close_asterion_observation.attack_slots.append(EnemyAISlot.new(&"elite_slot", Vector2(16, 0), 14.0, EnemyAIEnums.Role.ELITE))
	asterion.reset_decision_timer()
	var melee_decision: EnemyAIDecision = asterion.evaluate(close_asterion_observation, 0.2)
	_check(melee_decision.attack_id == &"asterion_melee", "Asterion chooses melee at close range")

	var blocked_observation: EnemyAIObservation = _pressure_observation(Vector2(20, 0))
	blocked_observation.target_reachable = false
	blocked_observation.has_fallback_position = true
	blocked_observation.fallback_position = Vector2(80, 20)
	asterion.reset_decision_timer()
	var blocked_decision: EnemyAIDecision = asterion.evaluate(blocked_observation, 0.2)
	_check(blocked_decision.intent == EnemyAIEnums.Intent.REPOSITION, "Asterion repositions when the target is unreachable")

	if _failures == 0:
		print("[AI SMOKE] all abstract enemy decisions passed")
	else:
		push_error("[AI SMOKE] %d decision checks failed" % _failures)
	minotaur.free()
	asterion.free()
	get_tree().quit(1 if _failures > 0 else 0)


func _pressure_observation(target: Vector2) -> EnemyAIObservation:
	var observation: EnemyAIObservation = EnemyAIObservation.new()
	observation.actor_id = &"test_actor"
	observation.self_position = Vector2.ZERO
	observation.self_radius = 8.0
	observation.target_position = target
	observation.target_valid = true
	observation.target_visible = true
	observation.target_reachable = true
	observation.objective = EnemyAIEnums.Objective.PRESSURE_TARGET
	observation.route_valid = true
	observation.route_direction = target.normalized()
	observation.line_of_sight_clear = true
	observation.chamber_active = true
	observation.refresh_distance()
	return observation


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[AI SMOKE] " + message)
