class_name EnemyAISlot
extends RefCounted

var slot_id: StringName = &""
var position: Vector2 = Vector2.ZERO
var radius: float = 12.0
var allowed_role: int = -1
var occupied_by: StringName = &""


func _init(
		id: StringName = &"",
		world_position: Vector2 = Vector2.ZERO,
		slot_radius: float = 12.0,
		role_filter: int = -1
	) -> void:
	slot_id = id
	position = world_position
	radius = maxf(slot_radius, 1.0)
	allowed_role = role_filter


func is_available_for(actor_role: int) -> bool:
	if not occupied_by.is_empty():
		return false
	return allowed_role < 0 or allowed_role == actor_role
