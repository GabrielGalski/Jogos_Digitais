extends Resource
## All amplitudes are logical screen pixels, independent of the selected zoom.

@export var enabled: bool = true
@export_range(0.0, 4.0, 0.05) var shot_kick: float = 0.65
@export_range(0.01, 0.5, 0.01) var shot_duration: float = 0.11
@export_range(0.0, 6.0, 0.05) var hit_kick: float = 1.40
@export_range(0.01, 0.5, 0.01) var hit_duration: float = 0.14
@export_range(0.0, 6.0, 0.05) var kill_kick: float = 2.20
@export_range(0.01, 0.5, 0.01) var kill_duration: float = 0.18
@export_range(0.0, 4.0, 0.05) var wall_kick: float = 0.30
@export_range(0.01, 0.5, 0.01) var wall_duration: float = 0.09
@export_range(0.0, 2.0, 0.05) var hit_shake: float = 0.45
@export_range(0.0, 2.0, 0.05) var kill_shake: float = 0.80
@export_range(0.0, 8.0, 0.05) var maximum_offset: float = 2.80
