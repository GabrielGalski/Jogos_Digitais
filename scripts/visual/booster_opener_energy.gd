extends Node2D
## Pixel-sized additive light, shafts and motes; works in GL Compatibility.

@export var ground_only: bool = false
var _energy: float = 0.0
var _pulse: float = 0.0
var _time: float = 0.0
var _aperture_width: float = 32.0
var _ground_texture: ImageTexture = null


func _ready() -> void:
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = additive
	if ground_only:
		_build_ground_texture()


func configure(aperture_width: float) -> void:
	_aperture_width = aperture_width


func set_energy(amount: float, pulse: float, elapsed: float) -> void:
	_energy = amount
	_pulse = pulse
	_time = floorf(elapsed * 12.0) / 12.0
	visible = amount > 0.001
	queue_redraw()


func _draw() -> void:
	if _energy <= 0.001:
		return
	if ground_only:
		_draw_ground()
	else:
		_draw_beam()


func _build_ground_texture() -> void:
	var light_image: Image = Image.create(160, 64, false, Image.FORMAT_RGBA8)
	for y: int in range(64):
		for x: int in range(160):
			var uv: Vector2 = Vector2((float(x) - 79.5) / 80.0, (float(y) - 31.5) / 32.0)
			var falloff: float = pow(maxf(0.0, 1.0 - uv.length()), 2.0)
			var alpha: float = floorf(falloff * 16.0) / 16.0
			light_image.set_pixel(x, y, Color(1.0, 0.06, 0.55, alpha))
	_ground_texture = ImageTexture.create_from_image(light_image)


func _draw_ground() -> void:
	var breathe: float = 0.9 + 0.1 * sin(_time * 2.3)
	draw_texture(_ground_texture, Vector2(-80, -18), Color(1, 1, 1, _energy * (0.65 + _pulse * 0.4) * breathe))
	var radii: Vector2 = Vector2(61, 20) + Vector2(9, 4) * _pulse
	var seen: Dictionary[Vector2i, bool] = {}
	for index: int in range(220):
		var angle: float = TAU * float(index) / 220.0
		var point: Vector2i = Vector2i((Vector2(cos(angle), sin(angle)) * radii + Vector2(0, 12)).round())
		if seen.has(point):
			continue
		seen[point] = true
		var phase: float = fposmod(angle - _time * 0.7, PI * 0.5)
		if phase < 0.9:
			draw_rect(Rect2(Vector2(point), Vector2.ONE), Color(1.0, 0.0, 0.58, _energy * (0.35 + _pulse * 0.4)))


func _draw_beam() -> void:
	var strength: float = _energy * (1.0 + _pulse * 0.7)
	var beam_height: int = roundi(43.0 * _energy)
	var breathe: float = 0.92 + sin(_time * 3.0) * 0.08
	# Layered two-pixel bands keep the broad glow on the sprite's own pixel grid.
	for rise: int in range(0, beam_height, 2):
		var height_ratio: float = float(rise) / 43.0
		var half_width: float = roundf(lerpf(_aperture_width * 0.43, 29.0, height_ratio))
		var fade: float = pow(1.0 - height_ratio, 1.7)
		draw_rect(Rect2(-half_width, -float(rise) - 2.0, half_width * 2.0, 2), Color(1.0, 0.74, 0.26, fade * 0.13 * strength * breathe))
		draw_rect(Rect2(-half_width * 0.65, -float(rise) - 2.0, roundf(half_width * 1.3), 2), Color(1.0, 0.90, 0.53, fade * 0.07 * strength))
	# Three distinct shafts rise out of the slit around the floating card.
	for shaft: int in range(3):
		var side: float = float(shaft - 1)
		var length: float = 38.0 if shaft == 1 else 30.0
		for rise: int in range(0, roundi(length * _energy), 2):
			var ratio: float = float(rise) / length
			var shaft_x: float = roundf(side * (8.0 + ratio * 7.0))
			var alpha: float = pow(1.0 - ratio, 0.7) * strength * 0.65
			draw_rect(Rect2(shaft_x - 2.0, -float(rise) - 2.0, 5, 2), Color(0.95, 0.58, 0.16, alpha * 0.26))
			draw_rect(Rect2(shaft_x, -float(rise) - 2.0, 1 if shaft != 1 else 2, 2), Color(1.0, 0.93, 0.62, alpha))
	for index: int in range(13):
		var travel: float = fposmod(_time * (8.0 + float(index % 4)) + float(index) * 7.7, 45.0)
		var phase: float = float(index) * 2.399
		var offset_x: float = sin(phase) * (9.0 + travel * 0.25) + sin(_time + phase) * 2.0
		var mote: Vector2 = Vector2(offset_x, -travel).round()
		var fade: float = sin(travel / 45.0 * PI) * strength
		var tint: Color = Color(1.0, 0.88, 0.40, fade * 0.8) if index % 4 != 0 else Color(1.0, 0.03, 0.6, fade * 0.65)
		var size_px: float = 2.0 if index % 5 == 0 else 1.0
		draw_rect(Rect2(mote, Vector2.ONE * size_px), tint)
