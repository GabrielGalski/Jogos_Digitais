extends CharacterBody3D

@export var move_speed: float = 5.0
@export var acceleration: float = 16.0
@export var gravity: float = 20.0
@export var mouse_sensitivity: float = 0.0022
@export_group("Dash")
@export var dash_speed: float = 10.5
@export var dash_duration: float = 0.12
@export var dash_cooldown: float = 0.18
@export_group("Dash Camera Effects")
@export var dash_fov_kick: float = 7.0
@export var dash_camera_offset: float = 0.08
@export var dash_camera_roll: float = 2.5
@export var dash_camera_pitch: float = 1.2
@export var dash_camera_recovery: float = 4.5
@export var dash_impact_position: float = 0.025
@export var dash_impact_rotation: float = 1.3
@export var dash_impact_fov: float = 2.0
@export var dash_impact_recovery: float = 5.5
@export var dash_effect_smoothing: float = 22.0
@export_group("Camera Tilt")
@export var camera_tilt_horizontal: float = 6.0
@export var camera_tilt_vertical: float = 4.0
@export var camera_tilt_response: float = 12.0

@onready var view_pivot: Node3D = $ViewPivot
@onready var camera_tilt: Node3D = $ViewPivot/CameraTilt
@onready var camera_effects: Node3D = $ViewPivot/CameraTilt/CameraEffects
@onready var camera: Camera3D = $ViewPivot/CameraTilt/CameraEffects/Camera3D

var spawn_position: Vector3
var base_camera_fov := 75.0
var dash_direction := Vector3.ZERO
var dash_local_direction := Vector3.ZERO
var dash_time_remaining := 0.0
var dash_cooldown_remaining := 0.0
var dash_camera_strength := 0.0
var dash_impact_strength := 0.0
var dash_effect_phase := 0.0


func _ready() -> void:
	spawn_position = global_position
	base_camera_fov = camera.fov
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		view_pivot.rotation.x = clamp(
			view_pivot.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-85.0),
			deg_to_rad(85.0)
		)

	if event.is_action_pressed(&"dash"):
		if event is InputEventKey and event.echo:
			return
		_start_dash()

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if (
		event is InputEventMouseButton
		and event.pressed
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var tilt_input := _get_camera_tilt_input()
	var target_pitch := tilt_input.y * deg_to_rad(camera_tilt_vertical)
	var target_roll := -tilt_input.x * deg_to_rad(camera_tilt_horizontal)
	var blend_weight := 1.0 - exp(-camera_tilt_response * delta)

	camera_tilt.rotation.x = lerp_angle(camera_tilt.rotation.x, target_pitch, blend_weight)
	camera_tilt.rotation.z = lerp_angle(camera_tilt.rotation.z, target_roll, blend_weight)
	_update_dash_camera_effects(delta)


func _physics_process(delta: float) -> void:
	dash_cooldown_remaining = maxf(dash_cooldown_remaining - delta, 0.0)
	var was_dashing := dash_time_remaining > 0.0
	var dash_ended_this_frame := false

	var input_vector := _get_movement_input()
	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	if dash_time_remaining > 0.0:
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		dash_time_remaining = maxf(dash_time_remaining - delta, 0.0)
		dash_ended_this_frame = dash_time_remaining <= 0.0
	else:
		var target_velocity := direction * move_speed
		velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	if was_dashing and is_on_wall():
		dash_time_remaining = 0.0
		dash_camera_strength = 0.0
		_trigger_dash_impact(1.0)
	elif dash_ended_this_frame:
		_trigger_dash_impact(0.18)

	if global_position.y < -25.0:
		_respawn()


func _start_dash() -> void:
	if dash_cooldown_remaining > 0.0 or dash_time_remaining > 0.0:
		return

	var input_vector := _get_movement_input()
	if input_vector.is_zero_approx():
		return

	dash_direction = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	dash_local_direction = Vector3(input_vector.x, 0.0, input_vector.y).normalized()
	dash_time_remaining = dash_duration
	dash_cooldown_remaining = dash_cooldown
	dash_camera_strength = 1.0
	_trigger_dash_impact(0.28)


func _trigger_dash_impact(strength: float) -> void:
	dash_impact_strength = maxf(dash_impact_strength, strength)
	dash_effect_phase += 1.7


func _update_dash_camera_effects(delta: float) -> void:
	dash_camera_strength = move_toward(
		dash_camera_strength,
		0.0,
		dash_camera_recovery * delta
	)
	dash_impact_strength = move_toward(
		dash_impact_strength,
		0.0,
		dash_impact_recovery * delta
	)
	dash_effect_phase += delta * 45.0

	var target_position := -dash_local_direction * dash_camera_offset * dash_camera_strength
	var target_rotation := Vector3(
		dash_local_direction.z * deg_to_rad(dash_camera_pitch) * dash_camera_strength,
		0.0,
		-dash_local_direction.x * deg_to_rad(dash_camera_roll) * dash_camera_strength
	)

	target_position.x += sin(dash_effect_phase * 1.7) * dash_impact_position * dash_impact_strength
	target_position.y += cos(dash_effect_phase * 2.3) * dash_impact_position * dash_impact_strength
	target_rotation.x += sin(dash_effect_phase * 2.0) * deg_to_rad(dash_impact_rotation) * dash_impact_strength
	target_rotation.z += cos(dash_effect_phase * 1.6) * deg_to_rad(dash_impact_rotation) * dash_impact_strength

	var blend_weight := 1.0 - exp(-dash_effect_smoothing * delta)
	camera_effects.position = camera_effects.position.lerp(target_position, blend_weight)
	camera_effects.rotation.x = lerp_angle(camera_effects.rotation.x, target_rotation.x, blend_weight)
	camera_effects.rotation.z = lerp_angle(camera_effects.rotation.z, target_rotation.z, blend_weight)

	var target_fov := (
		base_camera_fov
		+ dash_fov_kick * dash_camera_strength
		- dash_impact_fov * dash_impact_strength
	)
	camera.fov = lerpf(camera.fov, target_fov, blend_weight)


func _get_movement_input() -> Vector2:
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	var forward := Input.is_action_pressed("move_forward")
	var backward := Input.is_action_pressed("move_backward")
	var horizontal := (1.0 if right else 0.0) - (1.0 if left else 0.0)
	var vertical := (1.0 if backward else 0.0) - (1.0 if forward else 0.0)
	return Vector2(horizontal, vertical).normalized()


func _get_camera_tilt_input() -> Vector2:
	return Input.get_vector(
		"camera_tilt_left",
		"camera_tilt_right",
		"camera_tilt_up",
		"camera_tilt_down"
	)


func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	dash_time_remaining = 0.0
	dash_camera_strength = 0.0
	dash_impact_strength = 0.0
	camera_effects.transform = Transform3D.IDENTITY
	camera.fov = base_camera_fov
