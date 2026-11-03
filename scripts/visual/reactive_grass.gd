extends Node2D
## Grass stays on frame 1; one passage plays a short, non-looping rustle.

var visual: AnimatedSprite2D = null
var reaction_count: int = 0


func configure(frames: SpriteFrames, visual_offset: Vector2, flip: int, opacity: float) -> void:
	visual = AnimatedSprite2D.new()
	visual.name = "Grass"
	visual.centered = false
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.sprite_frames = frames
	visual.position = visual_offset
	visual.flip_h = (flip & 1) != 0
	visual.flip_v = (flip & 2) != 0
	visual.modulate.a = opacity
	add_child(visual)
	visual.animation_finished.connect(_rest)
	_rest()


func react() -> void:
	if visual == null or (visual.animation == &"rustle" and visual.is_playing()): return
	reaction_count += 1
	visual.play(&"rustle")


func _rest() -> void:
	visual.animation = &"idle"
	visual.stop()
	visual.frame = 0
