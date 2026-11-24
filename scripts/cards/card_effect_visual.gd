extends Node2D
## Short, scene-owned feedback. Damage is resolved by the card controller.
const BITE_FRAMES: SpriteFrames = preload("res://resources/visual/carnivorous_ground_frames.tres")
const GOLEM_FRAMES: SpriteFrames = preload("res://resources/visual/golem_core_explosion_frames.tres")
const BITE_WINDUP: float = 0.25
const BITE_RECOVERY: float = 0.50
const BITE_STRIKE_FRAME: int = 5
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
	if kind in [&"warning", &"mouth", &"blast"]:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if kind == &"blast":
		lifetime = GOLEM_FRAMES.get_frame_count(&"blast") / GOLEM_FRAMES.get_animation_speed(&"blast")
		var unshaded: CanvasItemMaterial = CanvasItemMaterial.new()
		unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = unshaded
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
		&"ember_burst":
			for index: int in range(6):
				var point: Vector2 = (Vector2.from_angle(TAU * index / 6.0) * (4.0 + 12.0 * (1.0 - fade))).round()
				draw_rect(Rect2(point, Vector2(2, 2)), Color(1.0, 0.65, 0.24, fade))
		&"blast":
			var frame: int = mini(floori(age * GOLEM_FRAMES.get_animation_speed(&"blast")), GOLEM_FRAMES.get_frame_count(&"blast") - 1)
			var texture: Texture2D = GOLEM_FRAMES.get_frame_texture(&"blast", frame)
			var world_scale: float = radius / 44.0
			draw_texture_rect(texture, Rect2(-Vector2(50, 50) * world_scale, texture.get_size() * world_scale), false)
		&"shockwave":
			var reach: float = radius * (1.0 - fade * fade)
			for i: int in range(8):
				var angle: float = TAU * i / 8.0
				draw_arc(Vector2.ZERO, maxf(2, reach), angle, angle + 0.55, 8, Color(1, 1, 1, fade * 0.55), 1.5)
		&"warning":
			_draw_bite(mini(BITE_STRIKE_FRAME - 1, int(age * BITE_FRAMES.get_animation_speed(&"bite"))))
		&"mouth":
			_draw_bite(BITE_STRIKE_FRAME + int(age * BITE_FRAMES.get_animation_speed(&"bite")))
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


func _draw_bite(frame: int) -> void:
	var index: int = mini(frame, BITE_FRAMES.get_frame_count(&"bite") - 1)
	var texture: Texture2D = BITE_FRAMES.get_frame_texture(&"bite", index)
	draw_texture(texture, -texture.get_size() * 0.5)
