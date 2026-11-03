extends Node2D
## Compact luminous shapes with smooth edges, continuous aim and tapered trails.

var model: ProceduralManifestationModel
var factory: ProceduralWeaponSpriteFactory
var direction: Vector2 = Vector2.RIGHT
var age: float = 0.0
var attached: bool = false
var core: Sprite2D = null
var halo: Sprite2D = null
var _last_frame: int = -1
var _last_direction: Vector2 = Vector2.ZERO


func configure(definition: ProceduralManifestationModel, sprites: ProceduralWeaponSpriteFactory, aim: Vector2) -> void:
	model = definition
	factory = sprites
	direction = aim
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = 3
	var opaque: CanvasItemMaterial = CanvasItemMaterial.new()
	opaque.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = opaque
	halo = Sprite2D.new()
	halo.name = "Halo"
	halo.texture = factory.glow_texture()
	halo.scale = Vector2.ONE * model.halo_size * 0.75 / 32.0
	halo.modulate = Color(model.body_color, model.halo_opacity)
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var additive: CanvasItemMaterial = opaque.duplicate() as CanvasItemMaterial
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = additive
	add_child(halo)
	core = Sprite2D.new()
	core.name = "Core32"
	core.material = opaque
	core.scale = Vector2.ONE * model.visual_scale * float(factory.SIZE) / float(factory.RENDER_SIZE)
	add_child(core)
	_refresh()


func _process(delta: float) -> void:
	age += delta
	_refresh()
	queue_redraw()


func _refresh() -> void:
	if core == null:
		return
	var frame: int = int(age * (10.0 if model.shape == ProceduralManifestationModel.Shape.MASS else 16.0)) % 4
	if frame != _last_frame or direction != _last_direction:
		core.texture = factory.texture_for(model, frame, Vector2.RIGHT)
		_last_frame = frame
		_last_direction = direction
	core.rotation = direction.angle()


func _draw() -> void:
	if model == null or attached:
		return
	var length: float = minf(model.trail_length * 0.7, age * model.card.projectile_speed)
	if length <= 2.0:
		return
	# Small overlapping segments taper in width and opacity away from the head.
	for index: int in range(8):
		var weight: float = float(index) / 8.0
		var start: Vector2 = -direction * lerpf(2.0, length, weight)
		var end: Vector2 = -direction * lerpf(2.0, length, float(index + 1) / 8.0)
		draw_line(start, end, Color(model.body_color, (1.0 - weight) * 0.65), lerpf(1.8, 0.3, weight), true)
		if index < 4:
			draw_line(start, end, Color(model.core_color, (1.0 - weight) * 0.8), 0.6, true)
