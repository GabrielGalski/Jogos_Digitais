extends Node2D
## Shared purple stone and static yellow inlays. Source PNGs stay intact.

const STONE: Shader = preload("res://shaders/warp_stone.gdshader")
const INSCRIPTIONS: Shader = preload("res://shaders/warp_inscriptions.gdshader")
const REGULAR_TEXTURE: Texture2D = preload("res://assets/tiles/structures/warp.png")
const CENTRAL_TEXTURE: Texture2D = preload("res://assets/tiles/structures/central_warp.png")
const FEET_OFFSET: Vector2 = Vector2(0, 3)
static var _masks: Dictionary[String, Texture2D] = {}

@export var central: bool = false
var plate: Sprite2D = null
var inscriptions: Sprite2D = null
var source_center: Vector2 = Vector2.ZERO
var _emission: ShaderMaterial = null


func _ready() -> void:
	if plate == null:
		configure(central, null, 1.0 if central else 0.5)


func configure(is_central: bool, texture: Texture2D = null, render_scale: float = 1.0) -> void:
	central = is_central
	if plate != null:
		return
	if texture == null:
		texture = CENTRAL_TEXTURE if central else REGULAR_TEXTURE
	scale = Vector2.ONE * render_scale
	source_center = Vector2(96, 106) if central else Vector2(48, 49)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate = Sprite2D.new()
	plate.name = "Stone"
	plate.texture = texture
	plate.centered = false
	plate.position = -source_center
	var stone_material: ShaderMaterial = ShaderMaterial.new()
	stone_material.shader = STONE
	plate.material = stone_material
	add_child(plate)
	inscriptions = Sprite2D.new()
	inscriptions.name = "Inscriptions"
	inscriptions.texture = _inscription_mask(texture, central)
	inscriptions.centered = false
	inscriptions.position = -source_center
	_emission = ShaderMaterial.new()
	_emission.shader = INSCRIPTIONS
	_emission.set_shader_parameter(&"emission_mask", inscriptions.texture)
	inscriptions.material = _emission
	add_child(inscriptions)


static func _inscription_mask(texture: Texture2D, is_central: bool) -> Texture2D:
	var key: String = texture.resource_path + (":central" if is_central else ":regular")
	if _masks.has(key):
		return _masks[key]
	var source: Image = texture.get_image()
	if source.is_compressed():
		source.decompress()
	var size: Vector2i = source.get_size()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(size.x * size.y)
	var mask: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0, 0, 0, 1))
	# Only enclosed alpha cutouts are inlays; the exterior remains transparent.
	for y: int in range(size.y):
		for x: int in range(size.x):
			var first_pixel: Vector2i = Vector2i(x, y)
			if visited[y * size.x + x] != 0 or source.get_pixelv(first_pixel).a >= 0.5:
				continue
			var pixels: Array[Vector2i] = [first_pixel]
			visited[y * size.x + x] = 1
			var outside: bool = false
			var cursor: int = 0
			while cursor < pixels.size():
				var point: Vector2i = pixels[cursor]
				cursor += 1
				if point.x == 0 or point.y == 0 or point.x == size.x - 1 or point.y == size.y - 1:
					outside = true
				for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var neighbour: Vector2i = point + step
					if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= size.x or neighbour.y >= size.y:
						continue
					var index: int = neighbour.y * size.x + neighbour.x
					if visited[index] == 0 and source.get_pixelv(neighbour).a < 0.5:
						visited[index] = 1
						pixels.append(neighbour)
			if outside:
				continue
			for point: Vector2i in pixels:
				if is_central:
					if Rect2i(48, 58, 96, 96).has_point(point):
						mask.set_pixelv(point, Color(0, 1, 0, 1))
				else:
					mask.set_pixelv(point, Color(1, 0, 0, 1) if Rect2i(34, 38, 29, 22).has_point(point) else Color(0, 1, 0, 1))
	var result: ImageTexture = ImageTexture.create_from_image(mask)
	_masks[key] = result
	return result


func supports_feet(local_feet: Vector2) -> bool:
	if central:
		return absf(local_feet.x) / 88.0 + absf(local_feet.y) / 80.0 <= 1.0 \
			or Rect2(-41, 68, 82, 77).has_point(local_feet)
	return (local_feet / Vector2(45, 32)).length_squared() <= 1.0
