extends Node2D
## A single cached solid shadow, fixed in world space and below the actors.

const FIELD: Script = preload("res://scripts/visual/tree_shadow_field.gd")
const SHADER: Shader = preload("res://shaders/tree_shadows.gdshader")
const PROFILE: Resource = preload("res://resources/visual/terrain/tree_shadows.tres")
var field: Dictionary = {}
var mask_sprite: Sprite2D = null


func configure(casters: Array, profile: Resource = PROFILE, use_cache: bool = true) -> void:
	set_process(false)
	set_physics_process(false)
	z_index = -11
	z_as_relative = false
	if mask_sprite != null:
		mask_sprite.free()
		mask_sprite = null
	field = FIELD.build(casters, profile, use_cache)
	if field.is_empty(): return
	var bounds: Rect2 = field.bounds as Rect2
	var shadow_material: ShaderMaterial = ShaderMaterial.new()
	shadow_material.shader = SHADER
	shadow_material.set_shader_parameter(&"strength", float(profile.get("strength")))
	shadow_material.set_shader_parameter(&"shadow_tint", profile.get("tint") as Color)
	mask_sprite = Sprite2D.new()
	mask_sprite.name = "MergedCanopyShadow"
	mask_sprite.centered = false
	mask_sprite.texture = ImageTexture.create_from_image(field.image as Image)
	# Reconstruct the curved contour between texels; the shader still outputs
	# only the solid shadow colour, so this does not introduce a penumbra.
	mask_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mask_sprite.position = bounds.position
	mask_sprite.scale = Vector2.ONE * float(field.sample_size)
	mask_sprite.material = shadow_material
	add_child(mask_sprite)
	set_meta(&"caster_count", int(field.caster_count))
	set_meta(&"cache_hit", bool(field.cache_hit))
	set_meta(&"mask_bytes", int(field.bytes))
	set_meta(&"build_ms", float(field.build_ms))


func sample_world(point: Vector2) -> float:
	if field.is_empty(): return 0.0
	var local: Vector2 = to_local(point)
	var bounds: Rect2 = field.bounds as Rect2
	if not bounds.has_point(local): return 0.0
	var pixel: Vector2i = Vector2i((local - bounds.position) / float(field.sample_size))
	return (field.image as Image).get_pixelv(pixel).r
