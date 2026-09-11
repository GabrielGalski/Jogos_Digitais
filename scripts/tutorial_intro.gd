extends Node2D
## Only directs the entrance; all map geometry is stored in the scene.

signal entrance_finished

@onready var player: CharacterBody2D = $Mox
@onready var stair: Sprite2D = $EntranceStair
@onready var camera: Camera2D = $Mox/Camera2D
var entrance_complete := false


func _ready() -> void:
	var destination := player.position
	var camera_offset := camera.position
	var camera_target := camera.global_position
	player.intro_locked = true
	camera.top_level = true
	camera.global_position = camera_target
	player.position = $EntranceStart.position
	player.reset_physics_interpolation()
	camera.reset_smoothing()
	player.body.play(&"run")
	var arrival := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	arrival.tween_property(player, "position", destination, player.position.distance_to(destination) / player.movement_speed)
	await arrival.finished
	player.body.play(&"idle")
	var retract := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	retract.set_parallel(true)
	retract.tween_property(stair, "position:y", stair.position.y + 48.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	retract.tween_property(stair, "scale:y", 0.12, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	retract.tween_property(stair, "modulate:a", 0.0, 0.35).set_delay(0.35)
	await retract.finished
	stair.hide()
	camera.top_level = false
	camera.position = camera_offset
	camera.reset_physics_interpolation()
	camera.reset_smoothing()
	player.intro_locked = false
	entrance_complete = true
	entrance_finished.emit()
