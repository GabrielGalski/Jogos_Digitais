extends RefCounted
const SHADER: Shader = preload("res://shaders/biome_enemy_palette.gdshader")
const FROM: Dictionary[StringName, Array] = {
	&"flying_skull": ["#F1934C", "#FEFFE5", "#81173F"],
	&"slime": ["#422490", "#4477FF", "#4CC5E4", "#8BF5C6", "#FEFFE5", "#120A1A"],
}
static var _cache: Dictionary[String, Texture2D] = {}


static func targets(kind: StringName) -> PackedColorArray:
	if kind == &"flying_skull":
		return PackedColorArray([Color("#F1934C"), Color("#FEFFE5"), Color("#81173F")])
	return PackedColorArray([Color("#315767"), Color("#90DDD0"), Color("#B2EADC"),
		Color("#D2F2E9"), Color("#F0FAEF"), Color("#142B35")])


static func material_for(kind: StringName) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	var source: PackedColorArray = PackedColorArray()
	var destination: PackedColorArray = targets(kind)
	for color: String in FROM[kind] as Array: source.append(Color(color))
	material.set_shader_parameter(&"color_count", source.size())
	while source.size() < 6: source.append(Color.TRANSPARENT)
	while destination.size() < 6: destination.append(Color.TRANSPARENT)
	material.set_shader_parameter(&"from_colors", source)
	material.set_shader_parameter(&"to_colors", destination)
	return material


static func remains_texture(source: Texture2D, kind: StringName) -> Texture2D:
	var key: String = "%s:%s" % [source.resource_path, kind]
	if _cache.has(key): return _cache[key]
	var image: Image = source.get_image().duplicate() as Image
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var destination: PackedColorArray = targets(kind)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.5:
				image.set_pixel(x, y, Color.TRANSPARENT)
				continue
			for index: int in range((FROM[kind] as Array).size()):
				if pixel.is_equal_approx(Color(str((FROM[kind] as Array)[index]))):
					image.set_pixel(x, y, destination[index])
					break
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
