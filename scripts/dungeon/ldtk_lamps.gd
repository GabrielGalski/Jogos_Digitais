extends RefCounted
## LDtk lamp markers use the foot of the post as their anchor.

const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
const PROP_COVER: Script = preload("res://scripts/combat/projectile_prop_cover.gd")
const ART: Texture2D = preload("res://assets/tiles/floor/lamp/lamp.png")
const LIGHT: Texture2D = preload("res://resources/visual/booster_opener_light.tres")
const FOOT: Vector2 = Vector2(11.0, 45.0)
const BULB: Vector2 = Vector2(20.5, 18.5)


static func build(arena: Node2D, layers: Array, terrain_height: Callable) -> void:
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)) or str(layer.get("__type", "")) != "Entities":
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "Lamp":
				continue
			var feet: Vector2 = ENTITIES.entity_rect(entity, offset).position + FOOT
			_add_lamp(arena, feet, terrain_height.call(arena.to_global(feet)) as float)


static func _add_lamp(arena: Node2D, feet: Vector2, elevation: float) -> void:
	var lamp: Node2D = Node2D.new()
	lamp.name = "Lamp"
	lamp.position = feet - Vector2(0.0, 8.0)
	lamp.z_index = 2
	lamp.add_to_group(&"ldtk_lamps")
	arena.add_child(lamp, true)
	var art: Sprite2D = Sprite2D.new()
	art.texture = ART
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.centered = false
	art.position = -FOOT + Vector2(0.0, 8.0 - elevation)
	lamp.add_child(art)
	PROP_COVER.attach(art)
	var bulb: PointLight2D = PointLight2D.new()
	bulb.name = "Bulb"
	bulb.position = art.position + BULB
	bulb.texture = LIGHT
	bulb.texture_scale = 0.78
	bulb.color = Color("#ffd46c")
	bulb.energy = 0.82
	lamp.add_child(bulb)
	_add_bulb_emission(bulb)


static func _add_bulb_emission(bulb: PointLight2D) -> void:
	var unshaded: CanvasItemMaterial = CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var additive: CanvasItemMaterial = unshaded.duplicate() as CanvasItemMaterial
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var halo: Sprite2D = Sprite2D.new()
	halo.name = "BulbHalo"
	halo.texture = LIGHT
	halo.scale = Vector2(0.17, 0.15)
	halo.modulate = Color(1.0, 0.47, 0.15, 0.62)
	halo.material = additive
	bulb.add_child(halo)
	var core: Polygon2D = Polygon2D.new()
	core.name = "BulbCore"
	core.polygon = PackedVector2Array([
		Vector2(-0.5, -2.5), Vector2(0.5, -2.5), Vector2(0.5, -1.5),
		Vector2(1.5, -1.5), Vector2(1.5, 1.5), Vector2(0.5, 1.5),
		Vector2(0.5, 2.5), Vector2(-0.5, 2.5), Vector2(-0.5, 1.5),
		Vector2(-1.5, 1.5), Vector2(-1.5, -1.5), Vector2(-0.5, -1.5),
	])
	core.color = Color("#fff29d")
	core.material = unshaded
	bulb.add_child(core)
	var motes: CPUParticles2D = CPUParticles2D.new()
	motes.name = "Fireflies"
	motes.amount = 6
	motes.lifetime = 3.2
	motes.preprocess = 1.6
	motes.fixed_fps = 12
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(15.0, 11.0)
	motes.direction = Vector2.UP
	motes.spread = 165.0
	motes.initial_velocity_min = 2.0
	motes.initial_velocity_max = 6.0
	motes.gravity = Vector2(1.2, -0.8)
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.0
	motes.material = unshaded
	var glow: Gradient = Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.24, 0.50, 0.72, 1.0])
	glow.colors = PackedColorArray([
		Color(1.0, 0.68, 0.25, 0.0), Color(1.0, 0.90, 0.54, 0.78),
		Color(1.0, 0.78, 0.32, 0.22), Color(1.0, 0.91, 0.61, 0.72), Color(1.0, 0.68, 0.25, 0.0),
	])
	motes.color_ramp = glow
	bulb.add_child(motes)
