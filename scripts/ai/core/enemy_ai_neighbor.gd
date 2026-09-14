class_name EnemyAINeighbor
extends RefCounted

var actor_id: StringName = &""
var position: Vector2 = Vector2.ZERO
var radius: float = 8.0
var role: int = EnemyAIEnums.Role.MELEE
var is_attacking: bool = false
var is_elite: bool = false


func _init(
		id: StringName = &"",
		world_position: Vector2 = Vector2.ZERO,
		body_radius: float = 8.0,
		actor_role: int = EnemyAIEnums.Role.MELEE
	) -> void:
	actor_id = id
	position = world_position
	radius = maxf(body_radius, 0.0)
	role = actor_role
