extends Node2D
## Scene-scoped weapon presentation shared by tutorial and training; combat is untouched.
const STYLE: Script = preload("res://scripts/visual/projectile_visual_profile.gd")
const PRESENTER: Script = preload("res://scripts/visual/projectile_presentation.gd")
const LIGHT_RIG: Script = preload("res://scripts/visual/arena_lighting_rig.gd")
const CORE_SHADER: Shader = preload("res://shaders/projectile_world_style.gdshader")
const HALO_SHADER: Shader = preload("res://shaders/projectile_pixel_halo.gdshader")
@export var profile: Resource = preload("res://resources/visual/projectile_world_style.tres")
@export var laser_beam_path: NodePath = NodePath("../ManifestationController/LaserBeam")
var core_material: ShaderMaterial
var halo_material: ShaderMaterial
var radial: Texture2D
var impact_lights: Array[PointLight2D] = []
var timers: PackedFloat32Array = PackedFloat32Array([0, 0, 0])
var pool_cursor: int = 0
var channel_light: PointLight2D
var beam: Line2D
var shot_light: PointLight2D
var shot_source: Node2D
var shot_remaining: float = 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	radial = LIGHT_RIG.make_radial_texture()
	core_material = ShaderMaterial.new()
	core_material.shader = CORE_SHADER
	for key: String in ["shadow_color", "midtone_color", "highlight_color", "world_palette_mix"]:
		core_material.set_shader_parameter(key, profile.get(key))
	halo_material = ShaderMaterial.new()
	halo_material.shader = HALO_SHADER
	for index: int in range(3):
		impact_lights.append(_make_light("Impact%d" % index, 24))
	channel_light = _make_light("ChannelLight", 48)
	shot_light = _make_light("WeaponPulse", 18)
	if not laser_beam_path.is_empty():
		beam = get_node_or_null(laser_beam_path) as Line2D
	if beam != null:
		beam.material = core_material

func _make_light(light_name: String, radius: float) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.name = light_name
	light.texture = radial
	light.texture_scale = radius / 64.0
	light.energy = 0.0
	light.range_z_min = -2
	light.range_z_max = 2
	light.shadow_enabled = false
	add_child(light)
	return light

func style_projectile(projectile: Node2D, code: StringName) -> void:
	var visual: Sprite2D = projectile.get_node_or_null("Visual") as Sprite2D
	if visual == null or projectile.has_meta(&"world_styled"):
		return
	projectile.set_meta(&"world_styled", true)
	var presentation: Node2D = PRESENTER.new() as Node2D
	presentation.name = "WorldPresentation"
	projectile.add_child(presentation)
	presentation.call(&"setup", projectile, visual, profile, radial, halo_material, core_material, STYLE.accent(code))
	projectile.connect(&"visual_impact", flash_impact)

func style_channel(effect: Node2D) -> void:
	if effect.has_meta(&"world_styled"):
		return
	effect.set_meta(&"world_styled", true)
	for child: Node in effect.get_children():
		if child is CanvasItem:
			(child as CanvasItem).material = core_material

func flash_impact(at: Vector2, code: StringName) -> void:
	var light: PointLight2D = impact_lights[pool_cursor]
	light.global_position = at
	light.color = STYLE.accent(code)
	timers[pool_cursor] = float(profile.impact_duration)
	pool_cursor = (pool_cursor + 1) % impact_lights.size()

func flash_shot(source: Node2D, code: StringName) -> void:
	shot_source = source
	shot_remaining = float(profile.shot_duration)
	shot_light.global_position = source.global_position
	shot_light.color = STYLE.accent(code)
	shot_light.energy = float(profile.shot_energy)

func _process(delta: float) -> void:
	shot_remaining = maxf(0.0, shot_remaining - delta)
	if is_instance_valid(shot_source):
		shot_light.global_position = shot_source.global_position
	shot_light.energy = float(profile.shot_energy) * shot_remaining / maxf(float(profile.shot_duration), 0.001)
	for index: int in range(impact_lights.size()):
		timers[index] = maxf(0.0, timers[index] - delta)
		impact_lights[index].energy = float(profile.impact_energy) * timers[index] / float(profile.impact_duration)
	channel_light.energy = 0.0
	if is_instance_valid(beam) and beam.visible and beam.points.size() >= 2:
		channel_light.global_position = beam.to_global(beam.points[0].lerp(beam.points[1], 0.5))
		channel_light.color = STYLE.accent(&"M04")
		channel_light.energy = 0.20
	for effect: Node in get_tree().get_nodes_in_group(&"banshee_bursts"):
		if get_parent().is_ancestor_of(effect):
			style_channel(effect as Node2D)
			channel_light.global_position = (effect as Node2D).to_global(Vector2(48, 0))
			channel_light.color = STYLE.accent(&"M03")
			channel_light.energy = 0.12
	for effect: Node in get_tree().get_nodes_in_group(&"manifestation_projectiles"):
		if not get_parent().is_ancestor_of(effect) or effect.get("mode") != &"M08":
			continue
		if bool(effect.get("firing")):
			channel_light.global_position = (effect as Node2D).to_global(Vector2(45, 0))
			channel_light.color = STYLE.accent(&"M08")
			channel_light.energy = 0.24
