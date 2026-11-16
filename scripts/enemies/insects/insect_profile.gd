class_name InsectProfile
extends Resource
## Each species is independently tunable; damage follows the game's units of three.

@export var kind: StringName = &"little"
@export var maximum_health: float = 9.0
@export var damage: int = 6
@export var movement_speed: float = 54.0
@export var acceleration: float = 300.0
@export var body_radius: float = 5.0
@export_range(0.5, 2.0, 0.05) var visual_scale: float = 1.0
@export var attack_range: float = 21.0
@export var attack_reach: float = 25.0
@export var windup: float = 0.14
@export var active_duration: float = 0.10
@export var recovery: float = 0.25
@export var attack_cooldown: float = 0.40
@export var impact_frame: int = 3
@export var lunge_speed: float = 96.0
@export var retreat_duration: float = 0.9
@export var retreat_distance: float = 58.0
@export var knockback_resistance: float = 0.45


func attack_duration() -> float:
	return windup + active_duration + recovery
