class_name WaterSurface
extends Node2D
## Reusable visual water. Receives region descriptions, never LDtk or gameplay.

const WATER_SHADER: Shader = preload("res://shaders/water_voronoi.gdshader")
const REGION_SCENE: PackedScene = preload("res://scenes/visual/water_region.tscn")
const LAKE: WaterProfile = preload("res://resources/visual/water/lake.tres")
const RIVER: WaterProfile = preload("res://resources/visual/water/river.tres")
const SEA: WaterProfile = preload("res://resources/visual/water/sea.tres")

@export var profiles: Array[WaterProfile] = [LAKE, RIVER, SEA]
@export var mask_catalog: Dictionary[String, Texture2D] = {
	"Pond": preload("res://assets/visual/water/pond_mask.png"),
}
@export var report_diagnostics: bool = true
var regions: Array[Node2D] = []
var diagnostics: Array[String] = []
var elapsed: float = 0.0
var _materials: Dictionary[String, ShaderMaterial] = {}
var _surfaces: Dictionary[String, String] = {}
var _rectangle_texture: ImageTexture = null


func _init() -> void:
	z_as_relative = false
	z_index = -80
	y_sort_enabled = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func configure(descriptions: Array[Dictionary], textures: RefCounted = null) -> void:
	clear_regions()
	var used_ids: Dictionary[String, bool] = {}
	for description: Dictionary in descriptions:
		var region_id: String = str(description.get("id", "region_%d" % regions.size()))
		if used_ids.has(region_id):
			_diagnose(region_id, "IID duplicado")
			continue
		used_ids[region_id] = true
		_add_region(description, region_id, textures)


func clear_regions() -> void:
	for region: Node2D in regions:
		remove_child(region)
		region.queue_free()
	regions.clear()
	_materials.clear()
	_surfaces.clear()
	diagnostics.clear()


func _add_region(description: Dictionary, region_id: String, textures: RefCounted) -> void:
	var rect: Rect2 = description.get("rect", Rect2()) as Rect2
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_diagnose(region_id, "Retangulo invalido")
		return
	var preset: String = str(description.get("preset", "Lake"))
	var profile: WaterProfile = _find_profile(preset)
	if profile == null:
		_diagnose(region_id, "Preset desconhecido: " + preset)
		return
	var problem: String = profile.validation_error()
	if not problem.is_empty():
		_diagnose(region_id, problem)
		return
	var mask_id: String = str(description.get("mask_id", "Rectangle"))
	var mask: Texture2D = description.get("mask_texture", null) as Texture2D
	if mask == null:
		mask = _find_mask(mask_id, textures)
	if mask == null:
		_diagnose(region_id, "Mascara desconhecida: " + mask_id)
		return
	if mask_id != "Rectangle" and not mask.get_size().is_equal_approx(rect.size):
		_diagnose(region_id, "Mascara %s exige tamanho nativo %s, recebeu %s" % [mask_id, mask.get_size(), rect.size])
		return
	var parameters: Dictionary = profile.shader_parameters()
	var material_key: String = var_to_str(parameters)
	var surface_id: String = str(description.get("surface_id", ""))
	if not surface_id.is_empty():
		if _surfaces.has(surface_id) and _surfaces[surface_id] != material_key:
			_diagnose(region_id, "SurfaceId %s usa configuracoes divergentes" % surface_id)
			return
		_surfaces[surface_id] = material_key
	if not _materials.has(material_key):
		var water_material: ShaderMaterial = ShaderMaterial.new()
		water_material.shader = WATER_SHADER
		for parameter: String in parameters:
			water_material.set_shader_parameter(parameter, parameters[parameter])
		water_material.set_shader_parameter(&"water_elapsed", elapsed)
		_materials[material_key] = water_material
	var region: Node2D = REGION_SCENE.instantiate() as Node2D
	region.name = "Region_" + region_id.validate_node_name()
	region.position = rect.position
	region.set_meta(&"region_id", region_id)
	region.set_meta(&"authored_rect", rect)
	region.set_meta(&"surface_id", surface_id)
	region.set_meta(&"preset", preset)
	region.set_meta(&"terrain_clipped", bool(description.get("clip_to_terrain", false)))
	var sprite: Sprite2D = region.get_node("Surface") as Sprite2D
	sprite.texture = mask
	sprite.scale = rect.size / mask.get_size()
	sprite.material = _materials[material_key]
	add_child(region)
	region.add_to_group(&"water_regions")
	regions.append(region)


func _find_profile(preset: String) -> WaterProfile:
	for profile: WaterProfile in profiles:
		if profile != null and str(profile.preset_id) == preset:
			return profile
	return null


func _find_mask(mask_id: String, textures: RefCounted) -> Texture2D:
	if mask_id == "Rectangle":
		if _rectangle_texture == null:
			var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			_rectangle_texture = ImageTexture.create_from_image(image)
		return _rectangle_texture
	var mask: Texture2D = mask_catalog.get(mask_id) as Texture2D
	if mask != null and textures != null and not mask.resource_path.is_empty():
		return textures.call(&"get_texture", mask.resource_path) as Texture2D
	return mask


func _diagnose(region_id: String, message: String) -> void:
	var diagnostic: String = "WaterArea %s: %s" % [region_id, message]
	diagnostics.append(diagnostic)
	if report_diagnostics:
		push_warning(diagnostic)


func _process(delta: float) -> void:
	set_elapsed(elapsed + delta)


func set_elapsed(seconds: float) -> void:
	if not is_finite(seconds):
		return
	elapsed = maxf(seconds, 0.0)
	for water_material: ShaderMaterial in _materials.values():
		water_material.set_shader_parameter(&"water_elapsed", elapsed)


func material_count() -> int:
	return _materials.size()
