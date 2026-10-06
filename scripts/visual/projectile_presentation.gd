extends Node2D
## One projectile sprite and a subtle emissive halo; no copies or afterimages.
var host: Node2D
var source: Sprite2D
var profile: Resource
var halo: Sprite2D

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

func _process(_delta: float) -> void:
	if not is_instance_valid(source) or not host.visible:
		hide()
		return
	halo.visible = host.get("phase") != &"attached"
