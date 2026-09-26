extends CharacterBody2D
class_name Player

signal damage_received(amount: float)
signal health_changed(current: float, maximum: float)
signal defeated
signal dash_started

@export_category("Dash")
@export var dash_speed: float = 330.0
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 0.65
var dash_remaining: float = 0.0
var dash_recovery: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT
var dash_trail_timer: float = 0.0
var dash_camera_strength: float = 0.0
var dash_camera_offset: Vector2 = Vector2.ZERO
var dash_visual_time: float = 0.0
var body_rest_scale: Vector2 = Vector2.ONE

@export_category("Combat balance")
@export var max_health: float = 60.0
var health: float = 60.0
var dead: bool = false
var hit_flash: Tween
var contact_invulnerability: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var impact_control_lock: float = 0.0

func receive_skybreaker_hit(amount: float) -> void:
	if dead or intro_locked or amount <= 0.0:
		return
	amount = ceilf(amount / 3.0) * 3.0
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	damage_received.emit(amount)
	if health <= 0.0:
		dead = true
		intro_locked = true
		velocity = Vector2.ZERO
		defeated.emit()
	if hit_flash and hit_flash.is_valid():
		hit_flash.kill()
	body.modulate = Color(2.8, 1.2, 1.2)
	hit_flash = create_tween()
	hit_flash.tween_property(body, "modulate", Color.WHITE, 0.25)

@export var movement_speed := 82.0
var card_movement_multiplier: float = 1.0
const CAMERA_ARENA_MARGIN := 32.0
@export var arena_bounds := Rect2(-336.0, -320.0, 672.0, 560.0)
# Local bounds account for the capsule's downward offset.
@export var movement_bounds := Rect2(-332.0, -318.0, 664.0, 550.0)
var intro_locked := false

@onready var body: AnimatedSprite2D = $Body


func _ready() -> void:
	health = max_health
	body_rest_scale = body.scale
	# Camera limits use world coordinates; movement bounds use arena coordinates.
	var arena := get_parent() as Node2D
	var camera: Camera2D = $Camera2D
	var top_left := arena.to_global(arena_bounds.position) - Vector2.ONE * CAMERA_ARENA_MARGIN
	var bottom_right := arena.to_global(arena_bounds.end) + Vector2.ONE * CAMERA_ARENA_MARGIN
	camera.limit_left = roundi(top_left.x)
	camera.limit_top = roundi(top_left.y)
	camera.limit_right = roundi(bottom_right.x)
	camera.limit_bottom = roundi(bottom_right.y)
	camera.make_current()
	camera.reset_smoothing()


func _physics_process(_delta: float) -> void:
	dash_recovery = maxf(dash_recovery - _delta, 0.0)
	contact_invulnerability = maxf(0.0, contact_invulnerability - _delta)
	impact_control_lock = maxf(0.0, impact_control_lock - _delta)
	if intro_locked:
		dash_remaining = 0.0
		velocity = Vector2.ZERO
		return
	var input_direction: Vector2 = Vector2.ZERO if impact_control_lock > 0.0 else _get_movement_input()
	if Input.is_action_just_pressed(&"dash"):
		try_dash(input_direction)
	if is_dashing():
		var step_time: float = minf(_delta, dash_remaining)
		velocity = dash_direction * dash_speed * step_time / maxf(_delta, 0.0001)
		move_and_slide()
		position = position.clamp(movement_bounds.position, movement_bounds.end)
		dash_remaining = maxf(0.0, dash_remaining - _delta)
		dash_trail_timer -= _delta
		if dash_trail_timer <= 0.0:
			_spawn_dash_trail()
			dash_trail_timer += 0.025
		_update_animation(dash_direction)
		if get_slide_collision_count() > 0:
			dash_remaining = 0.0
		return
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 480.0 * _delta)
	velocity = input_direction * movement_speed * card_movement_multiplier + knockback_velocity
	move_and_slide()
	position = position.clamp(movement_bounds.position, movement_bounds.end)
	_update_animation(input_direction)


func is_dashing() -> bool:
	return dash_remaining > 0.0


func try_dash(direction: Vector2 = Vector2.ZERO) -> bool:
	if dead or intro_locked or is_dashing() or dash_recovery > 0.0 or impact_control_lock > 0.0:
		return false
	dash_direction = direction.normalized()
	if dash_direction.is_zero_approx():
		dash_direction = Vector2.LEFT if body.flip_h else Vector2.RIGHT
	dash_remaining = dash_duration
	dash_recovery = dash_cooldown
	dash_trail_timer = 0.0
	knockback_velocity = Vector2.ZERO
	dash_camera_strength = 1.0
	_spawn_dash_trail()
	dash_started.emit()
	return true


func _process(delta: float) -> void:
	dash_visual_time += delta
	dash_camera_strength = move_toward(dash_camera_strength, 0.0, delta * 5.0)
	var camera: Camera2D = $Camera2D
	camera.position -= dash_camera_offset
	var kick: Vector2 = -dash_direction * 2.5
	var shake: Vector2 = Vector2(sin(dash_visual_time * 80.0), cos(dash_visual_time * 93.0)) * 0.65
	dash_camera_offset = (kick + shake) * dash_camera_strength if not intro_locked else Vector2.ZERO
	camera.position += dash_camera_offset
	var stretch: Vector2 = Vector2.ONE
	if is_dashing():
		stretch = Vector2(1.25, 0.8) if absf(dash_direction.x) >= absf(dash_direction.y) else Vector2(0.8, 1.25)
	body.scale = body.scale.lerp(body_rest_scale * stretch, 1.0 - exp(-24.0 * delta))
	body.rotation = lerp_angle(body.rotation, dash_direction.x * 0.12 if is_dashing() else 0.0, 1.0 - exp(-24.0 * delta))
	body.speed_scale = 2.0 if is_dashing() else 1.0


func _spawn_dash_trail() -> void:
	var trail: Sprite2D = Sprite2D.new()
	trail.name = "DashAfterimage"
	trail.add_to_group(&"dash_afterimages")
	trail.texture = body.sprite_frames.get_frame_texture(body.animation, body.frame)
	trail.flip_h = body.flip_h
	trail.texture_filter = body.texture_filter
	get_parent().add_child(trail)
	trail.global_transform = body.global_transform
	trail.z_index = z_index
	trail.modulate = Color(0.64, 0.35, 0.85, 0.48)
	var fade_trail: Tween = trail.create_tween()
	fade_trail.tween_property(trail, "modulate:a", 0.0, 0.22)
	fade_trail.tween_callback(trail.queue_free)


func set_movement_bounds(bounds: Rect2) -> void:
	movement_bounds = bounds


func _get_movement_input() -> Vector2:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	return direction.normalized()


func _update_animation(input_direction: Vector2) -> void:
	var next_animation: StringName = &"run" if not input_direction.is_zero_approx() else &"idle"
	if body.animation != next_animation:
		body.play(next_animation)
	if not is_zero_approx(input_direction.x):
		body.flip_h = input_direction.x < 0.0


func receive_contact_damage(amount: int, direction: Vector2 = Vector2.ZERO, knockback: float = 0.0) -> void:
	if intro_locked or contact_invulnerability > 0.0:
		return
	contact_invulnerability = 0.65
	if knockback > 0.0 and not direction.is_zero_approx():
		knockback_velocity = direction.normalized() * knockback
		impact_control_lock = 0.20
	receive_skybreaker_hit(float(amount))

func heal_full() -> void:
	if dead:
		return
	health = max_health
	contact_invulnerability = 0.0
	knockback_velocity = Vector2.ZERO
	impact_control_lock = 0.0
	health_changed.emit(health, max_health)
