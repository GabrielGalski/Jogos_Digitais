extends Node2D
## Minimal arrival presentation for the merchant door's platform preview.

@onready var player: Player = $Nox
@onready var camera: Camera2D = $Nox/Camera2D
@onready var fade: ColorRect = $Transition/Fade
@onready var training_minotaur: Minotaur = $TrainingMinotaur


func _ready() -> void:
	camera.zoom = Vector2(0.95, 0.95)
	player.dash_afterimages_enabled = false
	training_minotaur.max_resistance = INF
	training_minotaur.resistance = INF
	training_minotaur.velocity = Vector2.ZERO
	training_minotaur.training_dummy = true
	training_minotaur.training_home_position = training_minotaur.global_position
	training_minotaur.sprite.speed_scale = 0.0
	player.intro_locked = true
	fade.color = Color.BLACK
	var arrival: Tween = create_tween()
	arrival.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	arrival.tween_property(fade, "color:a", 0.0, 0.45)
	await arrival.finished
	player.intro_locked = false
