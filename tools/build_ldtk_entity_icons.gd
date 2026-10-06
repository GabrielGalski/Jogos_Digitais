extends SceneTree
## Offline editor-only atlas. The three source sprites remain untouched.

const OUTPUT: String = "res://assets/tiles/editor/ldtk_entities.png"
const SOURCES: PackedStringArray = [
	"res://assets/characters/player/idle/player_idle_01.png",
	"res://assets/merchant/character/merchant_idle1.png",
	"res://assets/enemies/minotaur/walk/minotaur_walk_01.png",
]

func _initialize() -> void:
	var atlas: Image = Image.create_empty(96, 32, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for index: int in range(SOURCES.size()):
		var source_path: String = ProjectSettings.globalize_path(SOURCES[index])
		var source: Image = Image.load_from_file(source_path)
		assert(source != null and not source.is_empty(), "Missing sprite: " + source_path)
		source.convert(Image.FORMAT_RGBA8)
		var used: Rect2i = source.get_used_rect()
		assert(used.size.x > 0 and used.size.y > 0, "Empty sprite: " + source_path)
		var crop: Image = source.get_region(used)
		var ratio: float = minf(28.0 / float(used.size.x), 30.0 / float(used.size.y))
		var width: int = maxi(1, roundi(float(used.size.x) * ratio))
		var height: int = maxi(1, roundi(float(used.size.y) * ratio))
		crop.resize(width, height, Image.INTERPOLATE_NEAREST)
		var top_left: Vector2i = Vector2i(index * 32 + (32 - width) / 2, 32 - height)
		atlas.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), top_left)
	assert(atlas.save_png(OUTPUT) == OK)
	print("LDtk entity icons saved: ", OUTPUT)
	quit()
