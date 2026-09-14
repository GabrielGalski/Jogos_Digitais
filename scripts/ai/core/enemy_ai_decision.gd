class_name EnemyAIDecision
extends RefCounted

var intent: int = EnemyAIEnums.Intent.IDLE
var movement_direction: Vector2 = Vector2.ZERO
var desired_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var attack_id: StringName = &""
var reserve_slot_id: StringName = &""
var lock_movement: bool = false
var reason: StringName = &""


func _init(next_intent: int = EnemyAIEnums.Intent.IDLE) -> void:
	intent = next_intent
