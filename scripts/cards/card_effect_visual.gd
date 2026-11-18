extends Node2D
## Short, scene-owned feedback. Damage is resolved by the card controller.
const MANDRAKE: Array[Texture2D] = [
	preload("res://assets/cards/mutacao/mandragora_de_bolso U04/mandrake/mandrake1.png"),
	preload("res://assets/cards/mutacao/mandragora_de_bolso U04/mandrake/mandrake2.png"),
	preload("res://assets/cards/mutacao/mandragora_de_bolso U04/mandrake/mandrake3.png"),
	preload("res://assets/cards/mutacao/mandragora_de_bolso U04/mandrake/mandrake4.png"),
]
var kind: StringName = &"blast"
var lifetime: float = 0.3
var radius: float = 18.0
var age: float = 0.0
var follow: Player
var copy_texture: Texture2D
var copy_offset: Vector2
var copy_scale: Vector2 = Vector2.ONE
var copy_flip: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 3
	if kind == &"copy":
		add_to_group(&"combat_decoys")


func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
	if is_instance_valid(follow):
		global_position = follow.surface_world_position() - Vector2(0, 32)
	queue_redraw()


func _draw() -> void:
	var fade: float = clampf(1.0 - age / lifetime, 0.0, 1.0)
	match kind:
		&"blast":
			for index: int in range(6):
				var mote: Vector2 = (Vector2.from_angle(TAU * index / 6.0) * radius * (1.0 - fade)).round()
				draw_rect(Rect2(mote, Vector2(2, 2)), Color(0.94, 0.78, 1.0, fade))
			draw_arc(Vector2.ZERO, radius * (0.4 + 0.6 * (1.0 - fade)), 0.0, TAU, 32, Color(0.94, 0.78, 1.0, fade), 2.0)
		&"shockwave":
			var reach: float = radius * (1.0 - fade * fade)
			for i: int in range(8):
				var angle: float = TAU * i / 8.0
				draw_arc(Vector2.ZERO, maxf(2, reach), angle, angle + 0.55, 8, Color(1, 1, 1, fade * 0.55), 1.5)
		&"warning":
			for i: int in range(8):
				var angle: float = TAU * i / 8.0
				draw_arc(Vector2.ZERO, radius, angle, angle + 0.48, 5, Color("#cb899f"), 1.0)
			draw_line(Vector2(-12, 1), Vector2(12, -1), Color("#371e36"), 2)
		&"mouth":
			var opening: float = maxf(0.12, sin(PI * clampf(age / lifetime + 0.12, 0, 1)))
			draw_set_transform(Vector2.ZERO, -0.13, Vector2(1, opening))
			var jaw := PackedVector2Array([Vector2(-25,0), Vector2(-17,-10), Vector2(-5,-13), Vector2(10,-11), Vector2(23,-5), Vector2(25,1), Vector2(13,11), Vector2(-6,13), Vector2(-18,8)])
			draw_colored_polygon(jaw, Color("#331b30"))
			jaw.append(jaw[0])
			draw_polyline(jaw, Color("#aa576f"), 2)
			for i: int in range(5):
				var x: float = -16 + i * 8
				var lip: float = 10 - absf(x) * 0.22
				for side: int in [-1, 1]:
					var base := Vector2(x + side, side * lip)
					draw_colored_polygon(PackedVector2Array([base, base + Vector2(5, 0), base + Vector2(2, -side * 6)]), Color("#f1d7b5"))
		&"smoke":
			var variation: float = fmod(position.x + position.y, 6.28)
			for i: int in range(5):
				var phase: float = variation + i * 2.4
				var drift := Vector2(cos(phase) * 9 + sin(age * 2 + phase) * 2, sin(phase) * 4 - age * (2 + i))
				var at := drift.round()
				var size := Vector2(6 - i, 4 - floori(i / 2.0))
				draw_rect(Rect2(at, size), Color(0.42, 0.23, 0.51, fade * 0.68))
				draw_rect(Rect2(at + Vector2(1,-1), Vector2(maxf(1,size.x-2),2)), Color(0.63, 0.77, 0.49, fade * 0.8))
		&"mandrake":
			var texture: Texture2D = MANDRAKE[mini(int(age * 10.0), 3)]
			var size: Vector2 = texture.get_size() * 0.65
			draw_texture_rect(texture, Rect2((-size * 0.5).round(), size.round()), false, Color(1, 1, 1, minf(fade * 4.0, 1.0)))
		&"copy":
			if copy_texture != null:
				var size: Vector2 = copy_texture.get_size() * copy_scale
				var rect: Rect2 = Rect2(copy_offset - size * 0.5, size)
				if copy_flip:
					rect.position.x += rect.size.x
					rect.size.x = -rect.size.x
				draw_texture_rect(copy_texture, rect, false, Color.WHITE)
