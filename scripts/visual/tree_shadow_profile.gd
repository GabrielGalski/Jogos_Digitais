extends Resource
## Static projected crowns and forest coverage. All sizes use world pixels.

@export_range(2, 8, 1) var world_pixels_per_texel: int = 2
@export var crown_scale: Vector2 = Vector2(1.12, 1.0)
@export var projection_direction: Vector2 = Vector2(-0.45, 0.9)
@export_range(0.0, 64.0, 1.0) var projection_length: float = 18.0
@export_range(0.2, 1.0, 0.05) var projection_compression: float = 0.55
@export_range(8.0, 128.0, 1.0) var crown_height_px: float = 48.0
@export var contact_radius: Vector2 = Vector2(9.0, 4.0)
@export_range(0.0, 24.0, 1.0) var forest_gap_px: float = 12.0
@export_range(16.0, 160.0, 4.0) var forest_max_link_distance: float = 100.0
@export_range(0.5, 1.5, 0.05) var forest_crown_scale: float = 1.0
@export_range(0.0, 0.6, 0.01) var strength: float = 0.18
@export var tint: Color = Color("#25131a")
