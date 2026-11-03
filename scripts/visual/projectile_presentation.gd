extends Node2D
## One projectile sprite and a subtle emissive halo; no copies or afterimages.
var host: Node2D
var source: Sprite2D
var profile: Resource
var halo: Sprite2D
const OUTER_GLOW: Script = preload("res://scripts/visual/sprite_outer_glow.gd")
var projectile_light: PointLight2D = null
var slime: bool = false

func setup(projectile: Node2D, visual: Sprite2D, style: Resource, radial: Texture2D, halo_material: ShaderMaterial, core_material: ShaderMaterial, accent: Color) -> void:
	host = projectile
	source = visual
	profile = style
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	source.material = core_material
	halo = Sprite2D.new()
	halo.texture = radial
	halo.material = halo_material
	halo.scale = Vector2.ONE * (0.24 if host.get("mode") == &"M02" else 0.16)
	halo.modulate = Color(accent, profile.halo_opacity)
	halo.z_index = -1
	add_child(halo)
	slime = host.get("mode") == &"M01"
	if slime:
		var additive: CanvasItemMaterial = CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		halo.material = additive
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		projectile_light = PointLight2D.new()
		projectile_light.texture = radial
		projectile_light.texture_scale = 0.18
		projectile_light.color = Color.WHITE
		projectile_light.shadow_enabled = false
		projectile_light.range_z_min = -2
		projectile_light.range_z_max = 2
		add_child(projectile_light)
		_sync_slime_glow()

func _process(_delta: float) -> void:
	if not is_instance_valid(source) or not host.visible:
		hide()
		return
	halo.visible = host.get("phase") != &"attached"
	if slime:
		_sync_slime_glow()


func _sync_slime_glow() -> void:
	halo.texture = OUTER_GLOW.texture_for(source.texture)
	halo.scale = source.scale
	halo.position = source.position + (source.offset * source.scale).rotated(source.rotation)
	halo.rotation = source.rotation
	halo.flip_h = source.flip_h
	halo.flip_v = source.flip_v
	var age: float = float(host.get("animation_clock"))
	var opacity: float = lerpf(0.65, 0.10, clampf(age / 0.45, 0.0, 1.0))
	if host.get("phase") == &"impact_ending":
		opacity *= source.modulate.a
	halo.modulate = Color(1, 1, 1, opacity)
	projectile_light.position = halo.position
	# Local illumination follows the core size, including the smaller settled bullet5.
	projectile_light.texture_scale = source.scale.x * 0.225
	projectile_light.energy = opacity * 0.24
