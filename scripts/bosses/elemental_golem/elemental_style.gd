extends RefCounted
## Elemental presentation uses the same rasterizer and warm cores as player weapons.
const COLORS: Array[Color] = [Color("b9f4ee"), Color("fa6a0a"), Color("ffe26b")]
const CORE: Color = Color("f6ede5")
const CACHE: StringName = &"elemental_weapon_style"

static func data() -> Dictionary:
	var tree: MainLoop = Engine.get_main_loop()
	if tree.has_meta(CACHE): return tree.get_meta(CACHE) as Dictionary
	var factory: ProceduralWeaponSpriteFactory = ProceduralWeaponSpriteFactory.new()
	var models: Array[ProceduralManifestationModel] = []
	for index: int in range(3):
		var model: ProceduralManifestationModel = ProceduralManifestationModel.new()
		model.body_color = COLORS[index]
		model.core_color = CORE
		model.shape = ProceduralManifestationModel.Shape.FIREBALL if index == 1 else ProceduralManifestationModel.Shape.LASER
		models.append(model)
		for frame: int in range(4): factory.texture_for(model,frame,Vector2.RIGHT)
	var result: Dictionary = {"factory":factory,"models":models}
	tree.set_meta(CACHE,result)
	return result

static func glow(parent: Node2D, size: Vector2, tint: Color) -> Sprite2D:
	var factory: ProceduralWeaponSpriteFactory = data().factory as ProceduralWeaponSpriteFactory
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = factory.glow_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = size / 32.0
	sprite.modulate = tint
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = additive
	parent.add_child(sprite)
	return sprite
