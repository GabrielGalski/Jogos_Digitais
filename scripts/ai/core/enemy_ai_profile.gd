class_name EnemyAIProfile
extends Resource

@export_category("Decision")
@export var think_interval: float = 0.12
@export var target_acquisition_radius: float = 480.0
@export var attack_range: float = 28.0
@export var preferred_distance: float = 36.0
@export var abandon_distance: float = 72.0
@export var attack_cooldown: float = 0.35

@export_category("Movement")
@export var personal_space: float = 16.0
@export var max_neighbors: int = 12
@export var movement_weight: float = 1.0
@export var separation_weight: float = 1.4
@export var fallback_weight: float = 1.0
@export var orbit_weight: float = 0.45

@export_category("Readability")
@export var preparation_duration: float = 0.35
@export var recovery_duration: float = 0.45
@export var attack_lock_duration: float = 0.2
