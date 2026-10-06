extends Node2D
## Soft world lights; the actual neon pixels and water remain emissive.
const RADIAL_RIG: Script = preload("res://scripts/visual/arena_lighting_rig.gd")
const EMISSION: Shader = preload("res://shaders/merchant_neon_emission.gdshader")
@export var profile: Resource = preload("res://resources/visual/merchant_lighting.tres")
@export var facade_source_path: NodePath = NodePath("../World/Toldo/Visual")
@export var door_source: Vector2 = Vector2(562.5, 150.5)
@export var water_origins: PackedVector2Array = PackedVector2Array([
	Vector2(70, 268), Vector2(275, 268), Vector2(480, 268),
	Vector2(685, 268), Vector2(890, 268)])
var radial: GradientTexture2D

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var ambient: CanvasModulate = CanvasModulate.new()
	ambient.name = "WorldAmbient"
	ambient.color = profile.get("ambient")
	add_child(ambient)
	radial = RADIAL_RIG.make_radial_texture()
	var facade_center: Vector2 = Vector2(337, 29)
	_light("FacadeNeon", facade_center, Vector2(150, 65), profile.get("facade_color"), float(profile.get("facade_energy")))
	_light("FacadeSpill", facade_center + Vector2(0, 62), Vector2(148, 82), profile.get("facade_color"), 0.16)
	_light("DoorNeon", door_source, Vector2(65, 28), profile.get("door_color"), float(profile.get("door_energy")))
	_light("DoorRim", door_source + Vector2(0, -32), Vector2(60, 68), profile.get("door_color"), 0.12)
	for index: int in range(water_origins.size()):
		_light("WaterRim%d" % index, water_origins[index], Vector2(145, 48), profile.get("water_color"), float(profile.get("water_energy")))
	var tin: Node2D = get_node("../World/Merchant") as Node2D
	var tin_light: PointLight2D = _light("TinKey", to_local(tin.global_position), Vector2(60, 52), profile.get("tin_color"), float(profile.get("tin_energy")))
	tin_light.range_item_cull_mask = 2
	var neon_sprite: Sprite2D = Sprite2D.new()
	neon_sprite.name = "FacadeEmission"
	neon_sprite.centered = false
	neon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	neon_sprite.z_index = 3
	var emission: ShaderMaterial = ShaderMaterial.new()
	emission.shader = EMISSION
	neon_sprite.material = emission
	add_child(neon_sprite)
	# The parent creates the water and applies its old Tin tint in _ready().
	_bind_presentation.call_deferred()

func _light(light_name: String, at: Vector2, radius: Vector2, tint: Color, strength: float) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.name = light_name
	light.texture = radial
	light.position = at
	light.scale = radius / 64.0
	light.color = tint
	light.energy = strength
	light.range_z_min = -2
	light.range_z_max = 30
	light.shadow_enabled = false
	add_child(light)
	return light

func _bind_presentation() -> void:
	var source: Sprite2D = get_node(facade_source_path) as Sprite2D
	var neon_sprite: Sprite2D = get_node("FacadeEmission") as Sprite2D
	neon_sprite.texture = source.texture
	neon_sprite.position = to_local(source.to_global(source.get_rect().position))
	var facade_center: Vector2 = to_local(source.to_global(source.get_rect().get_center()))
	(get_node("FacadeNeon") as PointLight2D).position = facade_center
	(get_node("FacadeSpill") as PointLight2D).position = facade_center + Vector2(0, 62)
	var tin: AnimatedSprite2D = get_node("../World/Merchant/Visual") as AnimatedSprite2D
	tin.modulate = Color.WHITE
	tin.light_mask = 3
	var threshold: Polygon2D = get_node("../World/HallDetails/DoorLight/Threshold") as Polygon2D
	threshold.color = profile.get("door_color")
	var emission: CanvasItemMaterial = CanvasItemMaterial.new()
	emission.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	threshold.material = emission
	var spill: Polygon2D = get_node("../World/HallDetails/DoorLight/Spill") as Polygon2D
	var floor_material: ShaderMaterial = spill.material.duplicate() as ShaderMaterial
	floor_material.set_shader_parameter("light_color", profile.get("door_color"))
	floor_material.set_shader_parameter("strength", 0.30)
	spill.material = floor_material
	var water: Sprite2D = get_node("../World/Water/Surface") as Sprite2D
	var water_material: ShaderMaterial = water.material as ShaderMaterial
	water_material.set_shader_parameter("neon_source_x", Vector2(to_global(facade_center).x - water.global_position.x, to_global(door_source).x - water.global_position.x))
	water_material.set_shader_parameter("night_level", 0.78)
	water_material.set_shader_parameter("neon_reflections", 0.28)
	water_material.set_shader_parameter("facade_reflection_color", profile.get("facade_color"))
	water_material.set_shader_parameter("door_reflection_color", profile.get("door_color"))
