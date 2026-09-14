extends Node2D

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	sprite.animation_finished.connect(queue_free)


func setup(
	from_position: Vector2,
	to_position: Vector2,
	use_right_variant: bool = false
) -> void:
	var displacement := to_position - from_position
	global_position = (from_position + to_position) * 0.5
	rotation = displacement.angle() - PI * 0.5
	scale = Vector2(1.0, maxf(displacement.length() / 60.0, 0.18))
	sprite.play(&"right" if use_right_variant else &"left")
	sprite.speed_scale = 1.3
	sprite.scale.x = 1.45
	var snap := create_tween()
	snap.tween_property(sprite, ^"scale:x", 1.0, 0.10).set_ease(Tween.EASE_OUT)
