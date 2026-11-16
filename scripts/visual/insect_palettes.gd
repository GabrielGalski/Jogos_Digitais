extends RefCounted
## Runtime proposals only. Source PNGs and their alpha/outline are never rewritten.
const SHADER: Shader = preload("res://shaders/insect_palette.gdshader")
const SOURCES: Array[Color] = [Color("#402751"), Color("#1E1D39"), Color("#3B1A3C"), Color("#9494B9")]
const UNIFORMS: Array[StringName] = [&"shell_light", &"shell_shade", &"cloth", &"blade"]
const LABELS: Array[String] = ["Monocromatico", "Cobre e gelo", "Casca clara"]
const PROPOSALS: Array[Dictionary] = [
	{
		&"tall": ["#D2AEC8", "#70526F", "#A889A3", "#F0E3EB"],
		&"fly": ["#D2AEC8", "#70526F", "#A889A3", "#F0E3EB"],
		&"little": ["#D2AEC8", "#70526F", "#A889A3", "#F0E3EB"],
	},
	{
		&"tall": ["#E4A07D", "#855151", "#B67761", "#F2DDC0"],
		&"fly": ["#A0C5DD", "#526780", "#6E8EAD", "#E7E2D4"],
		&"little": ["#C7BA80", "#74684A", "#A08D5F", "#EEE0B2"],
	},
	{
		&"tall": ["#DDD1AA", "#827052", "#AB9467", "#F3E6C5"],
		&"fly": ["#93B8CF", "#49687B", "#6C91A2", "#DBE3D4"],
		&"little": ["#D3B378", "#7A6246", "#AC8A5B", "#EEE0B2"],
	},
]
static var _remains_cache: Dictionary[String, Texture2D] = {}


static func apply(target: ShaderMaterial, kind: StringName, variant: int) -> void:
	var colors: Array = PROPOSALS[posmod(variant, PROPOSALS.size())][kind] as Array
	for index: int in range(UNIFORMS.size()):
		target.set_shader_parameter(UNIFORMS[index], Color(str(colors[index])))


static func remains_texture(source: Texture2D, kind: StringName, variant: int) -> Texture2D:
	# Cache at most one tiny final-frame texture per species/proposal, never per death.
	var source_key: String = source.resource_path if not source.resource_path.is_empty() else str(source.get_instance_id())
	var key: String = "%s:%s:%d" % [source_key, kind, posmod(variant, PROPOSALS.size())]
	if _remains_cache.has(key): return _remains_cache[key]
	var image: Image = source.get_image().duplicate() as Image
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var colors: Array = PROPOSALS[posmod(variant, PROPOSALS.size())][kind] as Array
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a <= 0.0: continue
			for index: int in range(SOURCES.size()):
				if pixel.is_equal_approx(SOURCES[index]):
					var replacement: Color = Color(str(colors[index]))
					replacement.a = pixel.a
					image.set_pixel(x, y, replacement)
					break
	var texture: Texture2D = ImageTexture.create_from_image(image)
	_remains_cache[key] = texture
	return texture
