class_name MinionAIProfile
extends EnemyAIProfile

@export_category("Minion")
@export var role: int = EnemyAIEnums.Role.MELEE
@export var attack_id: StringName = &"contact_attack"
@export var preferred_orbit_distance: float = 48.0
@export var can_attack_while_moving: bool = false
@export var use_attack_slots: bool = true
