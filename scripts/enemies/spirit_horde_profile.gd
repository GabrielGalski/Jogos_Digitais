extends Resource
## Balance in the game's three-point units. The current M01 + infusion hit is 6.

@export_range(1, 100, 1) var health_units: int = 1
@export var stage_speeds: PackedFloat32Array = PackedFloat32Array([48.0, 60.0, 72.0, 84.0])
@export var stage_damage_units: PackedInt32Array = PackedInt32Array([1, 2, 3, 4])
@export var stage_sway: PackedFloat32Array = PackedFloat32Array([0.0, 0.22, 0.38, 0.55])
@export_range(4, 100, 1) var maximum_alive: int = 36
@export_range(1, 30, 1) var initial_pack: int = 12
@export_range(0.1, 3.0, 0.05) var spawn_interval: float = 0.4 / 0.75
@export_range(16, 128, 1) var spawn_margin: float = 32.0
@export_range(0.1, 1.0, 0.05) var contact_slow_factor: float = 0.55
@export_range(0.05, 3.0, 0.05) var contact_slow_duration: float = 0.45
@export_range(0.0, 3.0, 0.05) var post_slow_invulnerability: float = 0.6


func health() -> float:
	return float(health_units * 3)


func speed(stage: int) -> float:
	return stage_speeds[clampi(stage, 0, stage_speeds.size() - 1)]


func damage(stage: int) -> int:
	return stage_damage_units[clampi(stage, 0, stage_damage_units.size() - 1)] * 3


func sway(stage: int) -> float:
	return stage_sway[clampi(stage, 0, stage_sway.size() - 1)]
