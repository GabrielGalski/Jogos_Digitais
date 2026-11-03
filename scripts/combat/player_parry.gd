extends Node2D
## Timed right-button defence, adapted from MonsterShift without global time scale.

const SLASH: Script = preload("res://scripts/combat/effects/parry_slash.gd")
const REVEAL: Shader = preload("res://shaders/player_parry_reveal.gdshader")
@export var parry_window: float = 0.15
@export var parry_cooldown: float = 0.42
@export var contact_radius: float = 12.0 * 1.15
@export var reflected_damage: float = 30.0
@export var recoil_distance: float = 48.0
@export var recoil_duration: float = 0.12
var combat_enabled: bool = true
var remaining: float = 0.0
var recovery: float = 0.0
var feedback_elapsed: float = -1.0
var _reveal_material: ShaderMaterial = null
var _previous_material: Material = null
var _recoil_direction: Vector2 = Vector2.ZERO
var _motion_origin: Vector2 = Vector2.ZERO
var _motion_distance: float = 0.0
var _motion_duration: float = 0.12
var _motion_elapsed: float = 0.0
var _motion_started: bool = false
var _wall_bounced: bool = false
var _camera_offset: Vector2 = Vector2.ZERO
@onready var player: Player = get_parent() as Player
@onready var body: NoxVisual = player.body
@onready var camera: Camera2D = player.get_node("Camera2D") as Camera2D


func _ready() -> void:
	process_physics_priority = 1
	_reveal_material = ShaderMaterial.new()
	_reveal_material.shader = REVEAL
	player.parry = self
	player.defeated.connect(cancel)


func _input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
		if begin():
			get_viewport().set_input_as_handled()


func begin() -> bool:
	if not combat_enabled or player.dead or player.intro_locked or recovery > 0.0 or feedback_active():
		return false
	remaining = parry_window
	recovery = parry_cooldown
	_scan_nearby()
	return true


func feedback_active() -> bool:
	return feedback_elapsed >= 0.0


func try_enemy_attack(attacker: Node2D, contact_point: Vector2) -> bool:
	if remaining <= 0.0 or not combat_enabled or player.dead or player.intro_locked or not is_instance_valid(attacker):
		return false
	if contact_point.distance_to(player.global_position) > contact_radius + 3.0:
		return false
	remaining = 0.0
	_succeed(attacker, attacker.global_position.direction_to(player.global_position))
	var target: Node2D = attacker
	if not target.has_method("take_damage"):
		target = attacker.get_parent() as Node2D
	if is_instance_valid(target) and target.has_method("take_damage"):
		target.call("take_damage", reflected_damage)
	if is_instance_valid(attacker) and attacker.has_method("receive_impact"):
		attacker.call("receive_impact", player.global_position.direction_to(attacker.global_position), 105.0, 0.1)
	return true


func try_projectile(projectile: Node2D) -> bool:
	if remaining <= 0.0 or not combat_enabled or player.dead or player.intro_locked or not is_instance_valid(projectile) or not projectile.has_method("parry"):
		return false
	if projectile.global_position.distance_to(player.global_position) > contact_radius + 3.0:
		return false
	var recoil: Vector2 = projectile.global_position.direction_to(player.global_position)
	var physical: CharacterBody2D = projectile as CharacterBody2D
	if physical != null and not physical.velocity.is_zero_approx():
		recoil = physical.velocity.normalized()
	if not bool(projectile.call("parry", player)):
		return false
	remaining = 0.0
	_succeed(projectile, recoil)
	return true


func _scan_nearby() -> void:
	var candidates: Array[Node] = get_tree().get_nodes_in_group(&"parryable_projectiles")
	candidates.append_array(get_tree().get_nodes_in_group(&"minotaur_melee_attacks"))
	for candidate: Node in candidates:
		var attack: Node2D = candidate as Node2D
		if remaining <= 0.0:
			break
		if attack == null or attack.global_position.distance_to(player.global_position) > contact_radius + 3.0:
			continue
		if attack.is_in_group(&"parryable_projectiles"):
			try_projectile(attack)
		elif attack.has_method("parry"):
			attack.call("parry", player)


func _succeed(source: Node2D, recoil: Vector2) -> void:
	# End the slide material before capturing the pose restored after parry.
	body.end_roll()
	_previous_material = body.material
	feedback_elapsed = 0.0
	_recoil_direction = recoil.normalized() if not recoil.is_zero_approx() else -body.facing
	_motion_started = false
	_wall_bounced = false
	_motion_distance = 0.0
	player.dash_remaining = 0.0
	player.dash_camera_strength = 0.0
	player.knockback_velocity = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.contact_invulnerability = maxf(player.contact_invulnerability, 0.27)
	body.end_roll()
	body.animation_locked = true
	body.stop()
	body.animation = &"roll_ready"
	body.set_frame_and_progress(0, 0.0)
	body.flip_h = -_recoil_direction.x < 0.0
	body.scale = player.body_rest_scale
	body.rotation = 0.0
	if player.hit_flash != null and player.hit_flash.is_valid():
		player.hit_flash.kill()
	body.modulate = Color.WHITE
	body.material = _reveal_material
	_reveal_material.set_shader_parameter(&"reveal_progress", 0.0)
	for previous: Node in get_tree().get_nodes_in_group(&"parry_effects"):
		if previous is CanvasLayer:
			(previous as CanvasLayer).hide()
		previous.queue_free()
	var effect: CanvasLayer = SLASH.new() as CanvasLayer
	effect.call("configure", get_viewport_rect().size, player.get_global_transform_with_canvas() * Vector2(0.0, -2.0), 0.045)
	player.get_parent().add_child(effect)
	player.notify_parry_success(source)


func _physics_process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	recovery = maxf(0.0, recovery - delta)
	if player.dead or player.intro_locked or not combat_enabled:
		cancel()
		return
	if remaining > 0.0:
		_scan_nearby()
	if not feedback_active():
		return
	feedback_elapsed += delta
	if feedback_elapsed >= 0.045:
		if not _motion_started:
			_motion_started = true
			_begin_motion(_recoil_direction, recoil_distance, recoil_duration)
		_move_recoil(delta)
	if feedback_elapsed >= 0.09:
		_reveal_material.set_shader_parameter(&"reveal_progress", clampf((feedback_elapsed - 0.09) / 0.15, 0.0, 1.0))
	if feedback_elapsed >= 0.27 and _motion_distance <= 0.0:
		cancel()


func _begin_motion(direction: Vector2, distance: float, duration: float) -> void:
	_motion_origin = player.global_position
	_recoil_direction = direction.normalized()
	_motion_distance = distance
	_motion_duration = duration
	_motion_elapsed = 0.0


func _move_recoil(delta: float) -> void:
	if _motion_distance <= 0.0:
		return
	_motion_elapsed = minf(_motion_elapsed + delta, _motion_duration)
	var fraction: float = _motion_elapsed / _motion_duration
	var target: Vector2 = _motion_origin + _recoil_direction * _motion_distance * (1.0 - pow(1.0 - fraction, 2.0))
	var collision: KinematicCollision2D = player.move_and_collide(target - player.global_position)
	var normal: Vector2 = collision.get_normal() if collision != null else Vector2.ZERO
	var clamped: Vector2 = player.position.clamp(player.movement_bounds.position, player.movement_bounds.end)
	if not clamped.is_equal_approx(player.position) and normal.is_zero_approx():
		normal = player.position.direction_to(clamped)
	player.position = clamped
	if not normal.is_zero_approx() and not _wall_bounced:
		_wall_bounced = true
		_begin_motion(normal, 16.0, 0.09)
	elif collision != null or fraction >= 1.0:
		_motion_distance = 0.0


func _process(_delta: float) -> void:
	var rig: Node = player.get_node_or_null("GameplayKit/GameplayCameraRig")
	if rig == null:
		camera.offset -= _camera_offset
	_camera_offset = _recoil_direction * 2.4 * maxf(0.0, 1.0 - (feedback_elapsed - 0.045) / 0.12) if feedback_active() and feedback_elapsed >= 0.045 else Vector2.ZERO
	if rig != null:
		rig.call("set_parry_offset", _camera_offset)
	else:
		camera.offset += _camera_offset


func cancel() -> void:
	remaining = 0.0
	if not feedback_active():
		return
	feedback_elapsed = -1.0
	_motion_distance = 0.0
	body.material = _previous_material
	_previous_material = null
	body.animation_locked = false
	body.reset_pose(body.facing)
	player.velocity = Vector2.ZERO


func _exit_tree() -> void:
	if is_instance_valid(camera):
		var rig: Node = player.get_node_or_null("GameplayKit/GameplayCameraRig")
		if rig != null:
			rig.call("set_parry_offset", Vector2.ZERO)
		else:
			camera.offset -= _camera_offset
