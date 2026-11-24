extends Node2D

enum Kind { GROUND_FIRE, RUNE_LINK }

const FRAMES: SpriteFrames = preload("res://resources/visual/calimshan_frames.tres")
const RUNES: Array[Texture2D] = [
	preload("res://assets/cards/sets/elementais_de_calimshan/mutacao/convergencia_primordial U08/runes/rune1.png"),
	preload("res://assets/cards/sets/elementais_de_calimshan/mutacao/convergencia_primordial U08/runes/rune2.png"),
]

static var _material: CanvasItemMaterial

var kind: Kind
var lifetime: float = 0.0
var radius: float = 0.0
var lightning_path: PackedVector2Array = PackedVector2Array()
var age: float = 0.0


static func play_sprite(parent: Node2D, clip: StringName, at: Vector2,
		sprite_scale: Vector2 = Vector2.ONE, offset: Vector2 = Vector2.ZERO) -> AnimatedSprite2D:
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.name = String(clip).to_pascal_case()
	sprite.sprite_frames = FRAMES
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.material = unshaded()
	sprite.z_index = 5
	sprite.scale = sprite_scale
	sprite.offset = offset
	parent.add_child(sprite)
	sprite.global_position = at.round()
	if not FRAMES.get_animation_loop(clip):
		sprite.animation_finished.connect(sprite.queue_free, CONNECT_ONE_SHOT)
	sprite.play(clip)
	return sprite


static func place_rune(parent: Node2D, at: Vector2, index: int) -> Sprite2D:
	var rune: Sprite2D = Sprite2D.new()
	rune.name = "PrimordialRune%d" % (index + 1)
	rune.texture = RUNES[index]
	rune.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rune.material = unshaded()
	rune.scale = Vector2(0.72, 0.5)
	rune.z_index = 1
	parent.add_child(rune)
	rune.global_position = at.round()
	return rune


static func unshaded() -> CanvasItemMaterial:
	if _material == null:
		_material = CanvasItemMaterial.new()
		_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _material


func _ready() -> void:
	material = unshaded()
	z_index = 1 if kind != Kind.RUNE_LINK else 3


func _process(delta: float) -> void:
	age += delta
	if lifetime > 0.0 and age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	match kind:
		Kind.GROUND_FIRE:
			_draw_fire()
		Kind.RUNE_LINK:
			_draw_lightning()


func _draw_fire() -> void:
	var alpha: float = minf(1.0, (1.0 - age / lifetime) * 3.0)
	draw_circle(Vector2.ZERO, radius, Color(0.87, 0.13, 0.20, 0.30 * alpha))


func _draw_lightning() -> void:
	if lightning_path.size() < 2:
		return
	var phase: float = floorf(age * 28.0)
	var points: PackedVector2Array = PackedVector2Array([lightning_path[0]])
	for index: int in range(1, lightning_path.size()):
		var from: Vector2 = lightning_path[index - 1]
		var endpoint: Vector2 = lightning_path[index]
		var count: int = maxi(1, ceili(from.distance_to(endpoint) / 9.0))
		var side: Vector2 = from.direction_to(endpoint).orthogonal()
		for step: int in range(1, count):
			var along: float = float(step) / float(count)
			var offset: float = sin(phase * 2.8 + float(index + step) * 4.1) * sin(along * PI) * 3.5
			points.append((from.lerp(endpoint, along) + side * offset).round())
		points.append(endpoint)
	draw_polyline(lightning_path, Color(0.09, 0.47, 0.59, 0.31), 5.0)
	draw_polyline(points, Color("#47cec6"), 2.5)
	draw_polyline(points, Color("#d6ffed"), 1.0)
