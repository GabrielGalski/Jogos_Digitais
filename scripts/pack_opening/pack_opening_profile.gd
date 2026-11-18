class_name PackOpeningProfile
extends Resource
## Local presentation tuning. No loot, inventory or audio state belongs here.

@export var pack_scale: float = 0.85
@export var cut_coverage: float = 0.85
@export var cut_tolerance: float = 9.0
@export var shake_pixels: float = 8.0
@export var shake_duration: float = 0.40
@export var particle_lifetime: float = 0.88
@export var back_particles: int = 132
@export var front_particles: int = 24
@export var burst_speed_min: float = 150.0
@export var burst_speed_max: float = 300.0
@export var burst_radius: float = 30.0
@export var burst_colors: PackedColorArray = PackedColorArray([
	Color("#ffe88a"), Color("#fff2d6"), Color("#e4a3ff"), Color("#ff72be")
])
@export var cut_color: Color = Color("#fff2d6")
@export var guide_color: Color = Color("#e4a3ff")
