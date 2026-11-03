extends CharacterBody2D
class_name Player

signal damage_received(amount: float)
signal health_changed(current: float, maximum: float)
signal defeated
signal dash_started
signal parry_succeeded(source: Node2D)
var parry: Node2D = null

@export_category("Dash")
@export var dash_speed: float = 495.0
# 495 px/s * (0.16 * 4/3) = 105.6 px: twice the previous travel distance.
@export var dash_duration: float = 0.16 * 4.0 / 3.0
# Recharge one spent charge every 0.5 s; no inter-dash cooldown.
@export var dash_cooldown: float = 0.5
@export var dash_afterimages_enabled: bool = true
const MAX_DASH_CHARGES: int = 2
var dash_charges: int = MAX_DASH_CHARGES
var dash_remaining: float = 0.0
var dash_recovery: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT
var dash_trail_timer: float = 0.0
var dash_camera_strength: float = 0.0
var dash_camera_offset: Vector2 = Vector2.ZERO
var dash_visual_time: float = 0.0
@export var dash_camera_kick: float = 3.6
@export var dash_camera_shake: float = 0.5
@export var dash_camera_recovery: float = 0.26
var body_rest_scale: Vector2 = Vector2.ONE
var _dash_previous_interpolation: Node.PhysicsInterpolationMode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
var _dash_interpolation_disabled: bool = false
var respawn_position: Vector2 = Vector2.ZERO

@export_category("Combat balance")
@export var max_health: float = 60.0
var health: float = 60.0
var dead: bool = false
var hit_flash: Tween
var contact_invulnerability: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var impact_control_lock: float = 0.0
var contact_slow_remaining: float = 0.0
var contact_slow_factor: float = 1.0

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
		return
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
var intro_locked: bool = false:
	set(value):
		intro_locked = value
		if value and is_node_ready():
			body.set_motion(Vector2.ZERO)

@export_category("Floor elevation")
@export var height_change_speed: float = 120.0
var floor_height: float = 0.0
var displayed_height: float = 0.0
var _rendered_floor_height: float = 0.0
var _floor_height_query: Callable = Callable()

@onready var body: NoxVisual = $Body


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
	_recover_dash_charges(_delta)
	contact_invulnerability = maxf(0.0, contact_invulnerability - _delta)
	contact_slow_remaining = maxf(0.0, contact_slow_remaining - _delta)
	if contact_slow_remaining <= 0.0:
		contact_slow_factor = 1.0
	impact_control_lock = maxf(0.0, impact_control_lock - _delta)
	if intro_locked:
		dash_remaining = 0.0
		_restore_dash_interpolation()
		body.end_roll()
		velocity = Vector2.ZERO
		_update_floor_height(_delta)
		return
	var input_direction: Vector2 = Vector2.ZERO if impact_control_lock > 0.0 else _get_movement_input()
	if Input.is_action_just_pressed(&"dash"):
		try_dash(input_direction)
	if is_dashing():
		var step_time: float = minf(_delta, dash_remaining)
		velocity = dash_direction * dash_speed * step_time / maxf(_delta, 0.0001)
		move_and_slide()
		position = position.clamp(movement_bounds.position, movement_bounds.end)
		_update_floor_height(_delta)
		dash_remaining = maxf(0.0, dash_remaining - _delta)
		dash_trail_timer -= _delta
		if dash_trail_timer <= 0.0:
			_spawn_dash_trail()
			dash_trail_timer += 0.05
		_update_animation(dash_direction)
		if get_slide_collision_count() > 0:
			dash_remaining = 0.0
		return
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 480.0 * _delta)
	velocity = input_direction * movement_speed * card_movement_multiplier * contact_slow_factor + knockback_velocity
	move_and_slide()
	position = position.clamp(movement_bounds.position, movement_bounds.end)
	_update_floor_height(_delta)
	_update_animation(input_direction)


func bind_floor_height(query: Callable) -> void:
	_floor_height_query = query
	snap_floor_height()


func snap_floor_height() -> void:
	_update_floor_height(0.0,true)
	reset_physics_interpolation()


func floor_visual_offset() -> Vector2:
	return Vector2(0,-_rendered_floor_height)


func surface_world_position() -> Vector2:
	return to_global(floor_visual_offset())


func _update_floor_height(delta: float, immediate: bool = false) -> void:
	floor_height = maxf(float(_floor_height_query.call(to_global(Vector2(0,3)))),0.0) if _floor_height_query.is_valid() else 0.0
	displayed_height = floor_height if immediate else move_toward(displayed_height,floor_height,height_change_speed*delta)
	var next_height: float = roundf(displayed_height)
	var shift: Vector2 = Vector2(0,_rendered_floor_height-next_height)
	_rendered_floor_height = next_height
	# Keep movement/collision on the ground plane; project the existing actor onto its floor.
	for child_name: String in ["Body","BoosterShooter","GroundShadow","RoomContactShadow"]:
		var visual: Node2D = get_node_or_null(child_name) as Node2D
		if visual != null:
			visual.position += shift


func is_dashing() -> bool:
	return dash_remaining > 0.0


func _recover_dash_charges(delta: float) -> void:
	if dash_charges >= MAX_DASH_CHARGES:
		dash_recovery = 0.0
		return
	if is_parry_feedback_active():
		velocity = Vector2.ZERO
		return
	dash_recovery -= delta
	while dash_recovery <= 0.0 and dash_charges < MAX_DASH_CHARGES:
		dash_charges += 1
		if dash_charges < MAX_DASH_CHARGES:
			dash_recovery += dash_cooldown
		else:
			dash_recovery = 0.0


func try_dash(direction: Vector2 = Vector2.ZERO) -> bool:
	if dead or intro_locked or is_parry_feedback_active() or is_dashing() or dash_charges <= 0 or impact_control_lock > 0.0:
		return false
	dash_direction = direction.normalized()
	if dash_direction.is_zero_approx():
		dash_direction = body.facing.normalized()
	# Spending the second charge must not restart the first charge's clock.
	if dash_charges == MAX_DASH_CHARGES:
		dash_recovery = dash_cooldown
	dash_charges -= 1
	dash_remaining = dash_duration
	# The first frame is spawned here; wait before creating the next one.
	dash_trail_timer = 0.05
	knockback_velocity = Vector2.ZERO
	dash_camera_strength = 1.0
	if not _dash_interpolation_disabled:
		_dash_previous_interpolation = physics_interpolation_mode
		_dash_interpolation_disabled = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reset_physics_interpolation()
	body.begin_roll(dash_direction)
	_update_animation(dash_direction)
	_spawn_dash_trail()
	dash_started.emit()
	return true


func _process(delta: float) -> void:
	dash_visual_time += delta
	dash_camera_strength = move_toward(dash_camera_strength, 0.0, delta / maxf(dash_camera_recovery, 0.001))
	if intro_locked or dead:
		dash_camera_strength = 0.0
	var camera: Camera2D = $Camera2D
	camera.position -= dash_camera_offset
	var kick: Vector2 = -dash_direction * dash_camera_kick
	var shake: Vector2 = dash_direction.orthogonal() * sin(dash_visual_time * 75.0) * dash_camera_shake
	dash_camera_offset = (kick + shake) * dash_camera_strength if not intro_locked else Vector2.ZERO
	camera.position += dash_camera_offset
	var stretch: Vector2 = Vector2.ONE
	if is_dashing() and not body.rolling:
		stretch = Vector2(1.25, 0.8) if absf(dash_direction.x) >= absf(dash_direction.y) else Vector2(0.8, 1.25)
	body.scale = body.scale.lerp(body_rest_scale * stretch, 1.0 - exp(-24.0 * delta))
	if not body.rolling and not body.animation_locked:
		body.rotation = lerp_angle(body.rotation, dash_direction.x * 0.12 if is_dashing() else 0.0, 1.0 - exp(-24.0 * delta))
	body.speed_scale = 1.0 if body.rolling else (2.0 if is_dashing() else 1.0)


func _spawn_dash_trail() -> void:
	if not dash_afterimages_enabled:
		return
	var trail: Sprite2D = Sprite2D.new()
	trail.name = "DashAfterimage"
	trail.add_to_group(&"dash_afterimages")
	trail.texture = body.sprite_frames.get_frame_texture(body.animation, body.frame)
	trail.flip_h = body.flip_h
	trail.centered = body.centered
	trail.offset = body.offset
	trail.texture_filter = body.texture_filter
	get_parent().add_child(trail)
	trail.global_transform = body.global_transform
	trail.reset_physics_interpolation()
	trail.z_index = z_index
	trail.modulate = Color(0.64, 0.35, 0.85, 0.48)
	var fade_trail: Tween = trail.create_tween()
	fade_trail.tween_property(trail, "modulate:a", 0.0, 0.22)
	fade_trail.tween_callback(trail.queue_free)


func set_movement_bounds(bounds: Rect2) -> void:
	movement_bounds = bounds


func set_respawn_position(point: Vector2) -> void:
	respawn_position = point


func fall_from_ldtk_gap() -> void:
	if dead or is_dashing():
		return
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	impact_control_lock = 0.0
	position = respawn_position
	snap_floor_height()
	dash_camera_strength = 0.0
	reset_physics_interpolation()
	var camera: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()


func _get_movement_input() -> Vector2:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	return direction.normalized()


func _update_animation(input_direction: Vector2) -> void:
	if is_dashing():
		body.set_roll_progress(1.0 - dash_remaining / maxf(dash_duration, 0.001))
	else:
		_restore_dash_interpolation()
		body.end_roll()
	body.set_motion(input_direction)


func _restore_dash_interpolation() -> void:
	if not _dash_interpolation_disabled:
		return
	physics_interpolation_mode = _dash_previous_interpolation
	_dash_interpolation_disabled = false
	reset_physics_interpolation()


func is_parry_feedback_active() -> bool:
	return is_instance_valid(parry) and bool(parry.call("feedback_active"))


func try_parry() -> bool:
	return is_instance_valid(parry) and bool(parry.call("begin"))


func notify_parry_success(source: Node2D) -> void:
	parry_succeeded.emit(source)


func try_parry_enemy_attack(attacker: Node2D, contact_point: Vector2) -> bool:
	return is_instance_valid(parry) and bool(parry.call("try_enemy_attack", attacker, contact_point))


func try_parry_projectile(projectile: Node2D) -> bool:
	return is_instance_valid(parry) and bool(parry.call("try_projectile", projectile))


func receive_contact_damage(amount: int, direction: Vector2 = Vector2.ZERO, knockback: float = 0.0) -> void:
	if intro_locked or contact_invulnerability > 0.0:
		return
	contact_invulnerability = 0.65
	if knockback > 0.0 and not direction.is_zero_approx():
		knockback_velocity = direction.normalized() * knockback
		impact_control_lock = 0.20
	receive_skybreaker_hit(float(amount))


func receive_projectile_damage(amount: int) -> bool:
	if dead or intro_locked or is_dashing() or contact_invulnerability > 0.0 or amount <= 0:
		return false
	# Brief projectile protection accepts distinct shots in a three-orb volley.
	# Existing contact/slow/parry protection is checked before this short window.
	contact_invulnerability = 0.14
	receive_skybreaker_hit(float(amount))
	return true


func apply_contact_slow(factor: float, duration: float, protected_after: float) -> void:
	if dead or intro_locked or duration <= 0.0:
		return
	contact_slow_factor = minf(contact_slow_factor, clampf(factor, 0.1, 1.0))
	contact_slow_remaining = maxf(contact_slow_remaining, duration)
	# Protect during the slow, then preserve a fresh window after movement recovers.
	contact_invulnerability = maxf(contact_invulnerability, contact_slow_remaining + maxf(protected_after, 0.0))

func heal_full() -> void:
	if dead:
		return
	health = max_health
	contact_invulnerability = 0.0
	contact_slow_remaining = 0.0
	contact_slow_factor = 1.0
	knockback_velocity = Vector2.ZERO
	impact_control_lock = 0.0
	health_changed.emit(health, max_health)
