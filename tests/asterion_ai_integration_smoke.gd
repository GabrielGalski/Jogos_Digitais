extends Node

const ARENA_SCENE: PackedScene = preload("res://scenes/tutorial_arena.tscn")

var _failures: int = 0


func _ready() -> void:
	var arena: Node2D = ARENA_SCENE.instantiate() as Node2D
	var boss: Variant = arena.get_node("MinotaurChair")
	boss.set("auto_start_encounter", false)
	add_child(arena)
	await get_tree().physics_frame

	var player: CharacterBody2D = arena.get_node("Mox") as CharacterBody2D
	var actor: CharacterBody2D = boss.get_node("Actor") as CharacterBody2D
	var body_collision: CollisionShape2D = actor.get_node("BodyCollision") as CollisionShape2D
	var ai: AsterionAI = boss.get_node("AI") as AsterionAI
	var sensor: EnemyAIWorldSensor2D = boss.get_node("AIWorldSensor") as EnemyAIWorldSensor2D
	player.set("intro_locked", true)
	player.global_position = Vector2(0.0, 80.0)
	player.reset_physics_interpolation()
	body_collision.disabled = false

	ai.special_cooldown_remaining = 999.0
	ai.attack_cooldown_remaining = 0.0
	ai.reset_decision_timer()
	actor.global_position = player.global_position + Vector2(24.0, 0.0)
	boss.call("_enter_chase")
	await get_tree().physics_frame
	_check(int(boss.get("state")) == 13, "Asterion selects the melee preparation state at close range")

	boss.call("_enter_chase")
	actor.global_position = player.global_position + Vector2(0.0, -160.0)
	ai.special_cooldown_remaining = 0.0
	ai.attack_cooldown_remaining = 0.0
	ai.reset_decision_timer()
	await get_tree().physics_frame
	_check(int(boss.get("state")) == 5, "Asterion selects Skybreaker at long range with a valid landing")

	boss.call("_enter_chase")
	player.global_position = Vector2(-80.0, -80.0)
	actor.global_position = Vector2(-270.0, -80.0)
	ai.special_cooldown_remaining = 999.0
	ai.attack_cooldown_remaining = 0.0
	ai.reset_decision_timer()
	await get_tree().physics_frame
	var obstacle_observation: EnemyAIObservation = sensor.build_observation(
		actor,
		player,
		EnemyAIEnums.Objective.PRESSURE_TARGET,
		32.0,
		true
	)
	var direct: Vector2 = (obstacle_observation.target_position - obstacle_observation.self_position).normalized()
	_check(obstacle_observation.route_valid, "Asterion finds a local route around arena collision")
	_check(absf(obstacle_observation.route_direction.cross(direct)) > 0.05, "Asterion changes direction instead of walking directly into the crater")

	ai.notify_special_attack_committed(3.5)
	ai.attack_cooldown_remaining = 0.0
	ai.reset_decision_timer()
	var cooldown_decision: EnemyAIDecision = ai.evaluate(obstacle_observation, 0.2)
	_check(cooldown_decision.attack_id != &"skybreaker", "Skybreaker cooldown does not block movement or force the special again")

	if _failures == 0:
		print("[ASTERION AI INTEGRATION] world sensing, melee and Skybreaker passed")
	else:
		push_error("[ASTERION AI INTEGRATION] %d checks failed" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[ASTERION AI INTEGRATION] " + message)