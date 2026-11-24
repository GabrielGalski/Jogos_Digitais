class_name ProceduralWeaponSpriteFactory
extends RefCounted
## Logical 32x32 recipes, rendered at 3x density for smooth, compact energy shapes.

const SIZE: int = 32
const RENDER_SIZE: int = 96
const DIRECTIONS: int = 32
const FRAMES: int = 4
const CACHE_LIMIT: int = 128
var _textures: Dictionary[String, Texture2D] = {}
var _glow: Texture2D = null


func texture_for(model: ProceduralManifestationModel, frame: int, direction: Vector2) -> Texture2D:
	var orientation: int = posmod(roundi(direction.angle() / TAU * DIRECTIONS), DIRECTIONS)
	var phase: int = posmod(frame, FRAMES)
	var key: String = "%d:%d:%d" % [model.get_instance_id(), phase, orientation]
	if _textures.has(key):
		return _textures[key]
	if _textures.size() >= CACHE_LIMIT:
		_textures.erase(_textures.keys()[0])
	var texture: ImageTexture = ImageTexture.create_from_image(_rasterize(model, phase, orientation, RENDER_SIZE, true))
	_textures[key] = texture
	return texture


func cache_size() -> int:
	return _textures.size()


func rasterize(model: ProceduralManifestationModel, frame: int, orientation: int = 0) -> Image:
	return _rasterize(model, frame, orientation, SIZE, false)


func _rasterize(model: ProceduralManifestationModel, frame: int, orientation: int, resolution: int, luminous: bool) -> Image:
	var pixels: Image = Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	var angle: float = -float(orientation) * TAU / DIRECTIONS
	# A colored rim replaces the heavy dark outline on runtime energy effects.
	var rim: Color = model.body_color.darkened(0.22) if luminous else model.shadow_color
	var colors: Array[Color] = [Color.TRANSPARENT, rim, model.body_color, model.core_color]
	for y: int in range(resolution):
		for x: int in range(resolution):
			var point: Vector2 = ((Vector2(x, y) + Vector2.ONE * 0.5) * float(SIZE) / float(resolution) - Vector2.ONE * 16.0).rotated(angle)
			var index: int = _shade(model.shape, point, posmod(frame, FRAMES))
			if index > 0:
				pixels.set_pixel(x, y, colors[index])
			elif luminous:
				# Color transparent texels too: linear filtering must not create a black fringe.
				pixels.set_pixel(x, y, Color(rim, 0.0))
	return pixels


func glow_texture() -> Texture2D:
	if _glow != null:
		return _glow
	var pixels: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var radius: float = (Vector2(x, y) - Vector2(15.5, 15.5)).length() / 16.0
			var alpha: float = pow(maxf(0.0, 1.0 - radius * radius), 3.0)
			pixels.set_pixel(x, y, Color(1, 1, 1, alpha))
	_glow = ImageTexture.create_from_image(pixels)
	return _glow


func _ellipse(point: Vector2, center: Vector2, radii: Vector2) -> float:
	return ((point - center) / radii).length()


func _shade(shape: int, point: Vector2, frame: int) -> int:
	var phase: float = float(frame) * PI * 0.5
	match shape:
		ProceduralManifestationModel.Shape.DROP:
			var outer: float = _ellipse(point, Vector2(1, 0), Vector2(5, 3.5))
			var tail: bool = point.x < -2.0 and point.x > -9.0 and absf(point.y) < (point.x + 10.0) * 0.24
			if outer > 1.0 and not tail: return 0
			if _ellipse(point, Vector2(2.0, -0.8), Vector2(2.2, 1.1)) < 1.0: return 3
			return 2 if outer < 0.77 or tail else 1
		ProceduralManifestationModel.Shape.MASS:
			var radius: float = 7.2 + sin(point.angle() * 5.0 + phase) * 0.7
			if point.length() > radius: return 0
			if _ellipse(point, Vector2(1.5, -2.0), Vector2(3.2, 1.8)) < 1.0: return 3
			return 2 if point.length() < radius - 1.0 else 1
		ProceduralManifestationModel.Shape.LASER:
			var radius: float = point.length()
			if radius > 4.0: return 0
			return 3 if radius < 1.8 else 2 if radius < 3.2 else 1
		ProceduralManifestationModel.Shape.SPIKE:
			if point.x < -9.0 or point.x > 10.0: return 0
			var width: float = (10.5 - point.x) * 0.18
			if absf(point.y) > width: return 0
			if absf(point.y + width * 0.25) < 0.65 and point.x > -5.0: return 3
			return 2 if absf(point.y) < width - 0.6 else 1
		ProceduralManifestationModel.Shape.FIREBALL:
			var head: float = _ellipse(point, Vector2(2, 0), Vector2(5.0, 4.0))
			var flame_width: float = (point.x + 14.0) * 0.25 + sin(point.x * 0.5 + phase) * 0.3
			var tail: bool = point.x > -14.0 and point.x < 2.0 and absf(point.y) < flame_width
			if head > 1.0 and not tail: return 0
			if _ellipse(point, Vector2(2.5, -0.5), Vector2(2.7, 1.8)) < 1.0: return 3
			return 2 if head < 0.85 or tail else 1
		ProceduralManifestationModel.Shape.PRISM:
			var half_width: float = minf((point.x + 8.0) * 0.64, (10.0 - point.x) * 0.58)
			if absf(point.y) >= half_width: return 0
			if point.x > -4.0 and point.x < 7.0 and absf(point.y + half_width * 0.27) < half_width * 0.31: return 3
			return 2 if point.y < half_width - 1.1 else 1
		ProceduralManifestationModel.Shape.LIGHT_PULSE:
			var length: float = absf(point.x)
			var width: float = 2.65 - maxf(0.0, length - 7.0) * 0.62
			if length > 11.0 or absf(point.y) > width: return 0
			if point.x > -7.0 and point.x < 4.5 and absf(point.y + 0.55) < 0.6: return 3
			return 2 if absf(point.y) < width - 0.45 else 1
		ProceduralManifestationModel.Shape.FANG:
			var sine: float = absf(point.y + point.x * point.x * 0.032 - 0.55)
			if point.x < -7.0 or point.x > 8.0 or sine > (9.0 - point.x) * 0.16: return 0
			if sine < 0.55 and point.x > -4.0: return 3
			return 2 if sine < 1.7 else 1
	return 0
