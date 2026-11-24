extends Node2D
## Shared stone warp and its two authored visual states.

const OFF: Texture2D = preload("res://assets/tiles/structures/warp/warp off.png")
const ON: Texture2D = preload("res://assets/tiles/structures/warp/warp on.png")
const CENTRAL_TEXTURE: Texture2D = preload("res://assets/tiles/structures/central warp/central_warp1.png")
const CENTRAL_PILLARS: Array[Texture2D] = [
	preload("res://assets/tiles/structures/central warp/central_warp4.png"),
	preload("res://assets/tiles/structures/central warp/central_warp5.png"),
	preload("res://assets/tiles/structures/central warp/central_warp3.png"),
	preload("res://assets/tiles/structures/central warp/central_warp2.png"),
]
const SOURCE_SIZE: Vector2 = Vector2(80, 80)
const SMALL_SCALE: float = 0.5625
const SOURCE_CENTER: Vector2 = Vector2(40, 39)
const CENTRAL_SOURCE_CENTER: Vector2 = Vector2(96, 106)
const FEET_OFFSET: Vector2 = Vector2(0, 3)
const TOP: Array[Vector2] = [
	Vector2(11, 22), Vector2(70, 22), Vector2(75, 29), Vector2(75, 48),
	Vector2(68, 54), Vector2(12, 54), Vector2(5, 48), Vector2(5, 29),
]
static var _central_base: ImageTexture

@export var central: bool = false
var plate: Sprite2D
var source_center: Vector2 = SOURCE_CENTER
var _particles: CPUParticles2D


func _ready() -> void:
	if plate == null:
		configure(central, 1.0 if central else SMALL_SCALE)


func configure(is_central: bool, render_scale: float = 1.0) -> void:
	central = is_central
	if plate != null:
		return
	scale = Vector2.ONE * render_scale
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	source_center = CENTRAL_SOURCE_CENTER if central else SOURCE_CENTER
	plate = Sprite2D.new()
	plate.name = "Stone"
	plate.texture = _central_base_texture() if central else OFF
	plate.centered = false
	plate.position = -source_center
	add_child(plate)


func set_active(active: bool) -> void:
	if central:
		return
	var texture: Texture2D = ON if active else OFF
	if plate.texture == texture:
		return
	plate.texture = texture
	if _particles == null:
		_build_particles()
	_particles.visible = active
	if active:
		_particles.restart()
	_particles.emitting = active


func _build_particles() -> void:
	_particles = CPUParticles2D.new()
	_particles.name = "WarpParticles"
	_particles.emitting = false
	_particles.local_coords = true
	_particles.amount = 16
	_particles.lifetime = 0.85
	_particles.preprocess = 0.30
	_particles.explosiveness = 0.25
	_particles.z_index = 3
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(20, 7)
	_particles.direction = Vector2.UP
	_particles.spread = 26.0
	_particles.initial_velocity_min = 16.0
	_particles.initial_velocity_max = 33.0
	_particles.gravity = Vector2(0, -5)
	_particles.scale_amount_min = 1.25
	_particles.scale_amount_max = 3.5
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.23, 0.68, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.64, 0.23, 0), Color("#f4b849"), Color("#f9e284"), Color(1, 0.88, 0.52, 0)])
	_particles.color_ramp = ramp
	var glow: CanvasItemMaterial = CanvasItemMaterial.new()
	glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_particles.material = glow
	add_child(_particles)


func supports_feet(local_feet: Vector2) -> bool:
	if central:
		return absf(local_feet.x) / 88.0 + absf(local_feet.y) / 80.0 <= 1.0 \
			or Rect2(-41, 68, 82, 77).has_point(local_feet)
	return Geometry2D.is_point_in_polygon(local_feet + SOURCE_CENTER, PackedVector2Array(TOP))


static func _central_base_texture() -> Texture2D:
	if _central_base == null:
		var base: Image = _read_image(CENTRAL_TEXTURE)
		# The full reference includes the posts. Only their separately sorted sprites draw these pixels.
		for texture: Texture2D in CENTRAL_PILLARS:
			var pillar: Image = _read_image(texture)
			var bounds: Rect2i = pillar.get_used_rect()
			for y: int in range(bounds.position.y, bounds.end.y):
				for x: int in range(bounds.position.x, bounds.end.x):
					if pillar.get_pixel(x, y).a > 0.0:
						base.set_pixel(x, y, Color.TRANSPARENT)
		_central_base = ImageTexture.create_from_image(base)
	return _central_base


static func _read_image(texture: Texture2D) -> Image:
	var image: Image = texture.get_image()
	if image.is_compressed():
		image.decompress()
	return image
