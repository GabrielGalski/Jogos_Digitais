class_name FlyingEyeProfile
extends Resource
## Three-point damage units. One small orb = 3, one complete volley = 9.

@export var maximum_health: float = 6.0
@export var orb_damage: int = 3
@export var movement_speed: float = 34.0
@export var acceleration: float = 140.0
@export var body_radius: float = 6.5
@export var preferred_distance: float = 88.0
@export var retreat_distance: float = 56.0
@export var attack_range: float = 160.0
@export var acquisition_range: float = 192.0
@export var anchor_leash: float = 264.0
@export var windup: float = 0.45
@export var shot_interval: float = 0.27
@export var turn_recovery: float = 0.85
@export var orb_speed: float = 116.0
@export var orb_lifetime: float = 3.4
@export var orb_radius: float = 3.0
@export_range(2, 5, 1) var minimum_pack_size: int = 2
@export_range(2, 5, 1) var maximum_pack_size: int = 5
@export_range(1, 2, 1) var maximum_packs_per_zone: int = 2
@export var minimum_anchor_distance: float = 320.0
@export var spawn_padding: float = 48.0
@export var spawn_attempts: int = 64
@export var spawn_interval: float = 0.35
@export var navigation_cell_size: float = 16.0


func full_volley_damage() -> int:
	return orb_damage * 3
