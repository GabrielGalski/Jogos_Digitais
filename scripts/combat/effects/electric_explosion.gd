extends Node2D

const VISUAL_SCALE_MULTIPLIER := 0.75

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	sprite.animation_finished.connect(queue_free)


func setup(center: Vector2, radius: float) -> void:
	global_position = center
	# A área de dano continua igual; somente a leitura visual fica 25% menor.
	var visual_scale := maxf(radius / 11.0 * VISUAL_SCALE_MULTIPLIER, 0.5)
	scale = Vector2.ONE * visual_scale
	sprite.play(&"explode")
	sprite.speed_scale = 1.25
	# A mesma animação abre rapidamente e dissipa; o raio de dano não muda.
	sprite.scale = Vector2.ONE * 0.45
	var burst := create_tween()
	burst.tween_property(sprite, ^"scale", Vector2.ONE * 1.18, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	burst.tween_property(sprite, ^"scale", Vector2.ONE, 0.13).set_ease(Tween.EASE_OUT)
