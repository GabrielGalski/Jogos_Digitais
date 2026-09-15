extends Node2D
## Only directs the entrance; all map geometry is stored in the scene.

signal entrance_finished

@onready var player: CharacterBody2D = $Mox
@onready var stair: Sprite2D = $EntranceStair
@onready var camera: Camera2D = $Mox/Camera2D
var entrance_complete := false
var exit_available: bool = false
var exiting: bool = false
var stair_home: Vector2
var stair_scale: Vector2
signal tutorial_exited


func _ready() -> void:
	stair_home = stair.position
	stair_scale = stair.scale
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

func restore_stair() -> void:
	if exit_available or exiting:
		return
	stair.show()
	var restore: Tween = create_tween().set_parallel(true)
	restore.tween_property(stair, "position", stair_home, 0.7)
	restore.tween_property(stair, "scale", stair_scale, 0.7)
	restore.tween_property(stair, "modulate:a", 1.0, 0.7)
	await restore.finished
	exit_available = true

func _physics_process(_delta: float) -> void:
	if exit_available and not exiting and not player.intro_locked and absf(player.position.x - stair_home.x) <= 18.0 and player.position.y >= player.movement_bounds.end.y - 12.0:
		leave_tutorial()

func leave_tutorial() -> void:
	if not exit_available or exiting:
		return
	exiting = true
	exit_available = false
	player.intro_locked = true
	player.velocity = Vector2.ZERO
	player.body.play(&"run")
	var departure: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	departure.tween_property(player, "position", $EntranceStart.position, 1.1)
	await departure.finished
	player.body.play(&"idle")
	tutorial_exited.emit()
