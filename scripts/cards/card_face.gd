class_name CardFace
extends Sprite2D
## Shared artwork and live text for the booster reveal and equipment screen.

const BODY_EXTENSION: int = 44
const BODY_INSERT_ROW: int = 165
const SOURCE_SIZE: Vector2i = Vector2i(208, 320)
const ART_BOUNDS: Rect2 = Rect2(6.0, 6.0, 196.0, 314.0 + BODY_EXTENSION)
const FRAME_PADDING: Vector2i = Vector2i(24, 24)
# Diamond bounds in the mask, measured without the transparent padding.
const ASPECT_REGION: Rect2i = Rect2i(80, 272, 48, 48)
const FACE_COLOR: Color = Color("#211e20")
const MATTE_PURPLE: Color = Color("#8963ab")
const RARE_PURPLE: Color = Color("#a657fa")
const LEGENDARY_PINK: Color = Color("#ff4aad")
const FRAME_MASK: Texture2D = preload("res://assets/visual/cards/preview/frame_mask.png")
const FRAME_HALO: Texture2D = preload("res://assets/visual/cards/preview/frame_halo.png")
const BOLD: FontFile = preload("res://assets/font/PixelifySans-Bold.ttf")
const MEDIUM: FontFile = preload("res://assets/font/PixelifySans-Medium.ttf")
const MODELS: Array[Texture2D] = [
	preload("res://assets/cards/base/new_models/base_manifestacao.png"),
	preload("res://assets/cards/base/new_models/base_infusao.png"),
	preload("res://assets/cards/base/new_models/base_mutacao.png"),
]
const ASPECT_NAMES: Array[String] = ["Manifestação", "Infusão", "Mutação"]

static var _body_textures: Array[Texture2D] = []
static var _matte_textures: Array[Texture2D] = []
static var _symbols: Array[Texture2D] = []
static var _outline_mask: ImageTexture
static var _halo_texture: ImageTexture
static var _title_font: FontFile
static var _text_font: FontFile

var _halo: Sprite2D
var _shadow: Sprite2D
var _foil: ShaderMaterial
var _rim: Line2D
var _symbol: Sprite2D
var _title: Label
var _description: Label
var _aspect: Label


func configure(card: CardDefinition) -> void:
	_prepare_assets()
	if _title == null:
		_build_face()

	var kind: int = card.get_kind()
	var rim_color: Color = MATTE_PURPLE
	var aspect_color: Color = Color("#bca2d1")
	match card.rarity:
		CardDefinition.Rarity.RARE:
			rim_color = RARE_PURPLE
			aspect_color = Color("#ceb2f6")
		CardDefinition.Rarity.LEGENDARY:
			rim_color = LEGENDARY_PINK
			aspect_color = Color("#ffb2da")
	var emissive: bool = card.rarity >= CardDefinition.Rarity.RARE
	texture = _body_textures[kind] if emissive else _matte_textures[kind]
	_shadow.texture = texture
	_foil.set_shader_parameter("border_tint", rim_color)
	material = _foil if emissive else null
	_halo.visible = emissive
	_halo.modulate = Color(rim_color, 0.55 if card.rarity == CardDefinition.Rarity.LEGENDARY else 0.47)

	_rim.default_color = rim_color
	_symbol.texture = _symbols[kind]
	_title.text = card.display_name
	_description.text = card.description
	var title_height: int = 0
	for line: int in _title.get_line_count():
		title_height += _title.get_line_height(line)
	_description.position.y = _title.position.y + float(title_height) + 10.0
	_aspect.text = ASPECT_NAMES[kind]
	_aspect.add_theme_color_override("font_color", aspect_color)


func _build_face() -> void:
	centered = false
	offset = -ART_BOUNDS.get_center()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow = Sprite2D.new()
	_shadow.name = "Shadow"
	_shadow.centered = false
	_shadow.offset = offset + Vector2(5.0, 7.0)
	_shadow.modulate = Color(0.0, 0.0, 0.0, 0.38)
	_shadow.show_behind_parent = true
	add_child(_shadow)

	_halo = Sprite2D.new()
	_halo.name = "Halo"
	_halo.texture = _halo_texture
	_halo.centered = false
	_halo.offset = offset - Vector2(FRAME_PADDING)
	_halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_halo.show_behind_parent = true
	add_child(_halo)

	_foil = ShaderMaterial.new()
	_foil.shader = CardTableCard.FOIL
	_foil.set_shader_parameter("foil_pattern", CardTableCard.PATTERN)
	_foil.set_shader_parameter("border_mask", _outline_mask)
	_foil.set_shader_parameter("strength", 0.88)

	_build_aspect_badge()
	_title = _make_label("CardTitle", Rect2(15.0, 33.0, 178.0, 62.0), _title_font, 22)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_constant_override("line_spacing", 0)
	_title.add_theme_color_override("font_color", Color("#fff7fd"))
	_description = _make_label("Description", Rect2(20.0, 0.0, 168.0, 160.0), _text_font, 16)
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_color_override("font_color", Color("#f1e9f3"))
	_description.add_theme_constant_override("line_spacing", 1)
	_aspect = _make_label("Aspect", Rect2(20.0, 249.0 + BODY_EXTENSION, 168.0, 23.0), _text_font, 15)


func _build_aspect_badge() -> void:
	var radius: float = float(ASPECT_REGION.size.x) * 0.5 - 1.5
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -radius), Vector2(radius, 0.0),
		Vector2(0.0, radius), Vector2(-radius, 0.0),
	])
	var badge: Polygon2D = Polygon2D.new()
	badge.name = "AspectBadge"
	badge.position = offset + Vector2(ASPECT_REGION.get_center()) + Vector2(0.0, BODY_EXTENSION)
	badge.polygon = points
	badge.color = FACE_COLOR
	badge.antialiased = true
	add_child(badge)

	_rim = Line2D.new()
	_rim.name = "Outline"
	_rim.points = points
	_rim.closed = true
	_rim.width = 2.0
	_rim.antialiased = true
	badge.add_child(_rim)

	_symbol = Sprite2D.new()
	_symbol.name = "Symbol"
	badge.add_child(_symbol)


func _make_label(node_name: String, bounds: Rect2, font: FontFile, font_size: int) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.clip_text = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.position = offset + bounds.position
	label.size = bounds.size
	add_child(label)
	return label


static func _prepare_assets() -> void:
	if not _body_textures.is_empty():
		return
	_title_font = BOLD.duplicate() as FontFile
	_title_font.multichannel_signed_distance_field = true
	_text_font = MEDIUM.duplicate() as FontFile
	_text_font.multichannel_signed_distance_field = true

	var frame_mask: Image = FRAME_MASK.get_image().get_region(Rect2i(FRAME_PADDING, SOURCE_SIZE))
	_restore_footer(frame_mask)
	frame_mask = _extend_body(frame_mask, BODY_INSERT_ROW)
	_outline_mask = ImageTexture.create_from_image(frame_mask)
	_halo_texture = ImageTexture.create_from_image(_extend_body(FRAME_HALO.get_image(),
		BODY_INSERT_ROW + FRAME_PADDING.y))
	for model: Texture2D in MODELS:
		var image: Image = model.get_image()
		_symbols.append(ImageTexture.create_from_image(_extract_symbol(image)))
		_restore_footer(image)
		image = _extend_body(image, BODY_INSERT_ROW)
		_body_textures.append(ImageTexture.create_from_image(image))
		for y: int in frame_mask.get_height():
			for x: int in frame_mask.get_width():
				if frame_mask.get_pixel(x, y).r > 0.5:
					image.set_pixel(x, y, MATTE_PURPLE)
		_matte_textures.append(ImageTexture.create_from_image(image))


static func _extract_symbol(model: Image) -> Image:
	var symbol: Image = model.get_region(ASPECT_REGION)
	var center: Vector2 = Vector2(ASPECT_REGION.size) * 0.5
	for y: int in symbol.get_height():
		for x: int in symbol.get_width():
			var distance: Vector2 = (Vector2(x + 0.5, y + 0.5) - center).abs()
			if distance.x + distance.y > center.x - 3.0 or symbol.get_pixel(x, y) == FACE_COLOR:
				symbol.set_pixel(x, y, Color.TRANSPARENT)
	return symbol


static func _restore_footer(image: Image) -> void:
	# Continue the horizontal frame behind the vector badge using a clean column.
	var start: Vector2i = ASPECT_REGION.position - Vector2i(1, 0)
	var column: Image = image.get_region(Rect2i(start, Vector2i(1, ASPECT_REGION.size.y)))
	column.resize(ASPECT_REGION.size.x, ASPECT_REGION.size.y, Image.INTERPOLATE_NEAREST)
	image.blit_rect(column, Rect2i(Vector2i.ZERO, column.get_size()), ASPECT_REGION.position)


static func _extend_body(source: Image, row: int) -> Image:
	var dimensions: Vector2i = source.get_size()
	var result: Image = Image.create_empty(dimensions.x, dimensions.y + BODY_EXTENSION, false, source.get_format())
	var top: Rect2i = Rect2i(0, 0, dimensions.x, row)
	var bottom: Rect2i = Rect2i(0, row, dimensions.x, dimensions.y - row)
	var strip: Image = source.get_region(Rect2i(0, row, dimensions.x, 1))
	strip.resize(dimensions.x, BODY_EXTENSION, Image.INTERPOLATE_NEAREST)
	result.blit_rect(source, top, Vector2i.ZERO)
	result.blit_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), Vector2i(0, row))
	result.blit_rect(source, bottom, Vector2i(0, row + BODY_EXTENSION))
	return result
