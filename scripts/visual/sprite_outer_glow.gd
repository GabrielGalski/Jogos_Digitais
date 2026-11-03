extends RefCounted
## Cached alpha-only bloom. Original PNGs are never rewritten or duplicated as actors.
const CACHE_KEY: StringName = &"monster_booster_outer_glow_cache"
const PADDING: int = 3

static func texture_for(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	# SceneTree owns generated textures, so closing the game releases the whole cache.
	# GDScript static dictionaries can retain resources past renderer shutdown.
	var loop: MainLoop = Engine.get_main_loop()
	var cache: Dictionary = loop.get_meta(CACHE_KEY, {}) as Dictionary
	if not loop.has_meta(CACHE_KEY):
		loop.set_meta(CACHE_KEY, cache)
	var key: int = source.get_instance_id()
	if cache.has(key):
		return cache[key] as Texture2D
	var pixels: Image = source.get_image()
	if pixels.is_compressed():
		pixels.decompress()
	var width: int = pixels.get_width()
	var height: int = pixels.get_height()
	var glow: Image = Image.create(width + PADDING * 2, height + PADDING * 2, false, Image.FORMAT_RGBA8)
	glow.fill(Color.TRANSPARENT)
	var weights: Array[float] = []
	var weight_sum: float = 0.0
	for offset: int in range(-PADDING, PADDING + 1):
		var weight: float = exp(-float(offset * offset) / 3.125)
		weights.append(weight)
		weight_sum += weight
	# Separable Gaussian: warm the cache without a frame hitch on the first shot.
	var horizontal: PackedFloat32Array = PackedFloat32Array()
	horizontal.resize(glow.get_width() * height)
	for y: int in range(height):
		for x: int in range(glow.get_width()):
			var alpha: float = 0.0
			for dx: int in range(-PADDING, PADDING + 1):
				var sample_x: int = x - PADDING + dx
				if sample_x >= 0 and sample_x < width:
					alpha += pixels.get_pixel(sample_x, y).a * weights[dx + PADDING]
			horizontal[y * glow.get_width() + x] = alpha / weight_sum
	for y: int in range(glow.get_height()):
		for x: int in range(glow.get_width()):
			var source_x: int = x - PADDING
			var source_y: int = y - PADDING
			var inside: float = pixels.get_pixel(source_x, source_y).a if source_x >= 0 and source_x < width and source_y >= 0 and source_y < height else 0.0
			if inside >= 0.99:
				continue
			var alpha: float = 0.0
			for dy: int in range(-PADDING, PADDING + 1):
				var sample_y: int = source_y + dy
				if sample_y < 0 or sample_y >= height:
					continue
				alpha += horizontal[sample_y * glow.get_width() + x] * weights[dy + PADDING]
			alpha = alpha / weight_sum * (1.0 - inside)
			glow.set_pixel(x, y, Color(1, 1, 1, alpha))
	var texture: ImageTexture = ImageTexture.create_from_image(glow)
	cache[key] = texture
	return texture
