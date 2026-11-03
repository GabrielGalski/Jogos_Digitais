extends Resource
## Small native-pixel scraps; all motion is cosmetic and independent of combat physics.
@export_range(1, 12, 1) var minimum_pieces: int = 4
@export_range(1, 12, 1) var maximum_pieces: int = 6
@export var fill_color: Color = Color("#BAC9CD")
@export var outline_color: Color = Color("#08080C")
@export var minimum_speed: float = 20.0
@export var maximum_speed: float = 48.0
@export var minimum_lift: float = 58.0
@export var maximum_lift: float = 88.0
@export var gravity: float = 300.0
@export var air_drag: float = 1.3
@export var ground_drag: float = 140.0
@export_range(0.0, 0.8, 0.05) var restitution: float = 0.28
@export var void_fall_duration: float = 0.22
@export_range(0.0, 120.0, 0.5) var lifetime: float = 15.0
@export_range(0.05, 2.0, 0.05) var fade_duration: float = 0.35
@export var kick_radius: float = 8.0
@export var kick_cooldown: float = 0.24
