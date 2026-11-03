extends Resource
## Room-local exposure and contact shadow. Original PNGs and gameplay stay unchanged.

@export var enabled: bool = true
@export_group("Circular visibility light")
@export var ambient_multiplier: Color = Color(0.92, 0.90, 0.96, 1.0)
@export var center_multiplier: Color = Color(1.12, 1.08, 1.16, 1.0)
@export_range(0.5, 1.5, 0.01) var saturation: float = 1.0
@export_range(16.0, 512.0, 0.1) var radius: float = 30.8
@export_range(0.0, 0.95, 0.01) var clear_center_ratio: float = 0.0
@export_range(0.0, 16.0, 1.0) var pixel_size: float = 2.0
@export_range(0, 16, 1) var brightness_steps: int = 0
@export var center_offset: Vector2 = Vector2(0.0, 4.0)
@export_group("Breathing and movement")
@export var breathing_enabled: bool = true
@export_range(0.3, 1.5, 0.01) var idle_radius_ratio: float = 0.78
@export_range(0.5, 2.0, 0.01) var moving_radius_ratio: float = 1.25
@export_range(1.0, 500.0, 0.1) var movement_reference_speed: float = 94.3
@export_range(0.05, 4.0, 0.05) var expansion_time: float = 0.3
@export_range(0.05, 6.0, 0.05) var contraction_time: float = 1.2
@export_range(1.0, 10.0, 0.1) var breathing_period: float = 3.6
@export_range(0.0, 0.15, 0.005) var breathing_amplitude: float = 0.035
@export_group("Ground contact shadow")
@export var contact_shadow_enabled: bool = true
@export var shadow_radii: Vector2 = Vector2(5.0, 2.0)
@export var shadow_offset: Vector2 = Vector2(0.0, 7.0)
@export var shadow_color: Color = Color(0.035, 0.015, 0.045, 0.42)
