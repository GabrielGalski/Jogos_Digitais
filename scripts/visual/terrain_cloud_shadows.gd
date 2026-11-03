extends Node
## One local clock and shared palette materials for the scene's ground layers.

var soil_material: ShaderMaterial = null
var cloud_elapsed: float = 0.0
var palette_materials: Dictionary[int, ShaderMaterial] = {}
var _additional_materials: Array[ShaderMaterial] = []


func configure(profile: ShaderMaterial, surfaces: Array[TileMapLayer]) -> void:
	if profile == null:
		return
	soil_material = profile.duplicate() as ShaderMaterial
	palette_materials[0] = soil_material
	for surface: TileMapLayer in surfaces:
		var palette: int = int(surface.get_meta(&"asset_palette", 0))
		if not palette_materials.has(palette):
			var variant: ShaderMaterial = soil_material.duplicate() as ShaderMaterial
			variant.set_shader_parameter(&"asset_palette", palette)
			palette_materials[palette] = variant
		surface.material = palette_materials[palette]


func _physics_process(delta: float) -> void:
	if soil_material == null:
		return
	set_elapsed(cloud_elapsed + delta)


func set_elapsed(elapsed: float) -> void:
	cloud_elapsed = elapsed
	for variant: ShaderMaterial in palette_materials.values():
		variant.set_shader_parameter(&"cloud_elapsed", cloud_elapsed)
	for variant: ShaderMaterial in _additional_materials:
		variant.set_shader_parameter(&"cloud_elapsed", cloud_elapsed)


func register_material(variant: ShaderMaterial) -> void:
	if variant != null and not _additional_materials.has(variant):
		variant.set_shader_parameter(&"cloud_elapsed", cloud_elapsed)
		_additional_materials.append(variant)
