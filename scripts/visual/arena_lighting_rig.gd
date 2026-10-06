extends Node2D
## Local crater lights, lower lights and encounter accents. No visible beams.
const PROFILE: Script = preload("res://scripts/visual/arena_lighting_profile.gd")
@export var profile: Resource = preload("res://resources/visual/tutorial_lighting.tres")
@export var lower_origins: PackedVector2Array = PackedVector2Array([Vector2(-260, 235), Vector2(260, 235)])
@export var chain_positions: PackedVector2Array = PackedVector2Array([Vector2(-208, -76), Vector2(-144, -34), Vector2(144, 32)])
@export var crater_regions: Array[Rect2] = []
var crater_lights: Array[PointLight2D] = []
var boss_light: PointLight2D
var impact_light: PointLight2D
var chain_light: PointLight2D
var lower_lights: Array[PointLight2D] = []
var crater_weight: float = 0.30
var chain_weight: float = 0.35
var boss_weight: float = 0.85
var target_weights: Vector3 = Vector3(0.30, 0.35, 0.85)
var impact_remaining: float = 0.0
var radial: GradientTexture2D

func _ready() -> void:
	if profile == null:
		profile = PROFILE.new()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var ambient_node: CanvasModulate = CanvasModulate.new()
	ambient_node.name = "WorldAmbient"
	ambient_node.color = profile.ambient
	add_child(ambient_node)
	radial = make_radial_texture()
	for region: Rect2 in crater_regions:
		var radius: Vector2 = region.size * 0.5 + Vector2.ONE * float(profile.crater_margin)
		crater_lights.append(_light("CraterLight%d" % crater_lights.size(), region.get_center(), radius, profile.crater_color))
	for origin: Vector2 in lower_origins:
		lower_lights.append(_light("LowerLight%d" % lower_lights.size(), origin + Vector2(0, -45), Vector2(110, 170), profile.lower_color))
	chain_light = _light("ChainRimLight", Vector2(0, -35), Vector2(260, 290), profile.lower_color)
	chain_light.range_z_min = 12
	chain_light.range_z_max = 20
	chain_light.enabled = not chain_positions.is_empty()
	boss_light = _light("AsterionLight", Vector2(0, -244), Vector2(100, 90), profile.boss_color)
	impact_light = _light("ImpactLight", Vector2.ZERO, Vector2(85, 65), profile.boss_color)
	impact_light.energy = 0.0
	update_lighting(0.0)

static func make_radial_texture() -> GradientTexture2D:
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.4, Color(1, 1, 1, 0.65))
	texture.gradient = ramp
	return texture

func _light(light_name: String, at: Vector2, radius: Vector2, tint: Color) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.name = light_name
	light.texture = radial
	light.position = at
	light.scale = radius / 64.0
	light.color = tint
	light.energy = 0.0
	light.range_z_min = -2
	light.range_z_max = 5
	light.shadow_enabled = false
	add_child(light)
	return light

func set_focus(craters: float, chains: float, boss: float) -> void:
	target_weights = Vector3(craters, chains, boss)

func flash_impact(at: Vector2) -> void:
	impact_light.global_position = at
	impact_remaining = profile.impact_duration

func update_lighting(delta: float) -> void:
	var blend: float = 1.0 - exp(-profile.transition_speed * delta)
	crater_weight = lerpf(crater_weight, target_weights.x, blend)
	chain_weight = lerpf(chain_weight, target_weights.y, blend)
	boss_weight = lerpf(boss_weight, target_weights.z, blend)
	for light: PointLight2D in crater_lights:
		light.energy = profile.crater_energy * crater_weight
	chain_light.energy = 0.36 * chain_weight
	boss_light.energy = profile.boss_energy * boss_weight
	for light: PointLight2D in lower_lights:
		light.energy = profile.lower_energy * chain_weight
	impact_remaining = maxf(0.0, impact_remaining - delta)
	impact_light.energy = profile.impact_energy * impact_remaining / profile.impact_duration

func _process(delta: float) -> void:
	update_lighting(delta)
