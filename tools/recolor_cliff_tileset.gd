extends SceneTree
## Geometry-locked palette export for the functional 16px cliff atlas.
## The generated colour study supplies the violet ramp; source pixels supply geometry.

const TARGET: String = "res://assets/tiles/floor/cliff_tileset.png"
const ORIGINAL: String = "res://assets/tiles/floor/source/cliff_tileset_original.png"
const RAMP: Array[Color] = [Color("#362338"), Color("#4b304b"), Color("#654065"), Color("#805880"), Color("#a077a0")]


func _initialize() -> void:
	var source: Image = Image.load_from_file(ORIGINAL)
	if source == null or source.get_size() != Vector2i(48, 80):
		push_error("Cliff source must remain the original 48x80 atlas.")
		quit(1)
		return
	source.convert(Image.FORMAT_RGBA8)
	var result: Image = source.duplicate() as Image
	var changed: int = 0
	var preserved: int = 0
	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			var color: Color = source.get_pixel(x, y)
			# Orange rock only. Purple ground, borders and every alpha value stay exact.
			if color.a8 != 255 or color.r8 - color.b8 < 48:
				preserved += 1
				continue
			var luminance: float = color.r8 * 0.2126 + color.g8 * 0.7152 + color.b8 * 0.0722
			var index: int = 0 if luminance < 112.0 else 1 if luminance < 125.0 else 2 if luminance < 139.0 else 3 if luminance < 154.0 else 4
			result.set_pixel(x, y, RAMP[index])
			changed += 1
	if changed < 900 or changed > 1400:
		push_error("Unexpected cliff source palette; no asset overwritten.")
		quit(1)
		return
	for y: int in range(source.get_height()):
		for x: int in range(source.get_width()):
			if source.get_pixel(x, y).a8 != result.get_pixel(x, y).a8:
				push_error("Cliff recolor changed source alpha.")
				quit(1)
				return
	if result.save_png(TARGET) != OK:
		push_error("Could not save recolored cliff atlas.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://output/castle_cliffs")
	var preview: Image = Image.create_empty(112, 80, false, Image.FORMAT_RGBA8)
	preview.fill(Color("#533048"))
	preview.blit_rect(source, Rect2i(0, 0, 48, 80), Vector2i.ZERO)
	preview.blit_rect(result, Rect2i(0, 0, 48, 80), Vector2i(64, 0))
	preview.resize(672, 480, Image.INTERPOLATE_NEAREST)
	preview.save_png("res://output/castle_cliffs/atlas_comparison.png")
	print("CLIFF_RECOLOR PASS | rock_pixels=%d | untouched_pixels=%d | exact alpha/geometry" % [changed, preserved])
	quit(0)
