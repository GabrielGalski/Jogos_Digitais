extends Node2D
## Decorative, world-anchored water. All animation runs in one GPU pass.
## Surface preserves the PNG footprint: (0, 295, 1024, 39).

@export_range(0.0, 30.0) var current_speed: float = 6.0
@export_range(0.1, 0.9) var distant_speed_ratio: float = 0.45
@export_range(0.5, 3.0) var pixel_size: float = 1.0
@export_range(0.0, 2.0) var ripple_strength: float = 1.0


func _ready() -> void:
	var surface: Sprite2D = get_node_or_null("Surface") as Sprite2D
	if surface == null:
		return
	var water_material: ShaderMaterial = surface.material as ShaderMaterial
	if water_material == null:
		return
	water_material.set_shader_parameter("water_size", surface.region_rect.size)
	water_material.set_shader_parameter("current_speed", current_speed)
	water_material.set_shader_parameter("distant_speed_ratio", distant_speed_ratio)
	water_material.set_shader_parameter("pixel_size", pixel_size)
	water_material.set_shader_parameter("ripple_strength", ripple_strength)
