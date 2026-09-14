class_name EliteAIProfile
extends EnemyAIProfile

@export_category("Elite")
@export var elite_id: StringName = &"elite"
@export var close_attack_id: StringName = &"close_attack"
@export var special_attack_id: StringName = &"special_attack"
@export var special_min_distance: float = 128.0
@export var special_cooldown: float = 2.0
@export var influence_radius: float = 220.0
@export var max_influenced_minions: int = 12
