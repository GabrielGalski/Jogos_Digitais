extends Node2D
## Four reusable ground glows/lights. Ground glows also work on the unshaded soil.

var sprites: Array[Sprite2D] = []
var lights: Array[PointLight2D] = []
var remaining: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0])
var durations: PackedFloat32Array = PackedFloat32Array([0.1, 0.1, 0.1, 0.1])
var cursor: int = 0


func configure(factory: ProceduralWeaponSpriteFactory) -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = -12
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for index: int in range(4):
		var glow: Sprite2D = Sprite2D.new()
		glow.texture = factory.glow_texture()
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		glow.material = additive
		glow.hide()
		add_child(glow)
		sprites.append(glow)
		var light: PointLight2D = PointLight2D.new()
		light.texture = factory.glow_texture()
		light.energy = 0.0
		light.shadow_enabled = false
		light.range_z_min = -25
		light.range_z_max = 5
		add_child(light)
		lights.append(light)


func flash(at: Vector2, model: ProceduralManifestationModel, impact: bool = false) -> void:
	if sprites.is_empty():
		return
	var index: int = cursor
	cursor = (cursor + 1) % 4
	durations[index] = 0.15 if impact else 0.075
	remaining[index] = durations[index]
	var radius: float = 25.0 if impact else 15.0
	sprites[index].global_position = at
	sprites[index].scale = Vector2.ONE * radius * 2.0 / 32.0
	sprites[index].modulate = Color(model.body_color, 0.16 if impact else 0.09)
	sprites[index].show()
	lights[index].global_position = at
	lights[index].color = model.body_color
	lights[index].texture_scale = radius * 2.0 / 32.0


func _process(delta: float) -> void:
	for index: int in range(sprites.size()):
		remaining[index] = maxf(0.0, remaining[index] - delta)
		var weight: float = remaining[index] / durations[index]
		sprites[index].visible = weight > 0.0
		sprites[index].self_modulate.a = weight
		lights[index].energy = weight * 0.22
