extends Node2D
## A floating miniboss. The bell strike emits one expanding wave with an open sector.
signal defeated

const ATLAS: Texture2D = preload("res://assets/enemies/bone_bell/spritesheet.png")
const FLASH: Shader = preload("res://shaders/white_damage_flash.gdshader")
const WINDUP_FRAMES: Array[float] = [0.09, 0.10, 0.115, 0.135]
const RELEASE_FRAMES: Array[float] = [0.12, 0.095, 0.10, 0.135]
const ATTACK_DISTANCE: float = 116.0
const WAVE_SPEED: float = 152.0
const WAVE_RANGE: float = 166.0
const WAVE_HALF_WIDTH: float = 5.0
const GAP_HALF_ANGLE: float = PI / 5.0
const DAMAGE: int = 6
const MAX_HEALTH: float = 30.0

enum Phase { HOVER, WINDUP, RING }

var player: Player
var health: float = MAX_HEALTH
var last_hit_direction: Vector2 = Vector2.DOWN
var phase: Phase = Phase.HOVER
var art: Sprite2D
var _flash_material: ShaderMaterial
var _flash_remaining: float = 0.0
var _drift: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _phase_age: float = 0.0
var _cooldown: float = 0.4
var _side: float = 1.0
var _gap_angle: float = 0.0
var _wave_origin: Vector2
var _wave_radius: float = 0.0
var _wave_live: bool = false
var _wave_hit: bool = false
var _previous_subject: Vector2


func _ready() -> void:
	add_to_group(&"enemy_bodies")
	add_to_group(&"bone_bells")
	set_meta(&"is_boss", true)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2
	art = Sprite2D.new()
	art.texture = ATLAS
	art.hframes = 4
	art.vframes = 3
	art.z_index = 4
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH
	art.material = _flash_material
	add_child(art)
	_previous_subject = _player_center()


func is_alive() -> bool:
	return health > 0.0 and not is_queued_for_deletion()


func get_current_health() -> float:
	return health


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": Vector2(0, -2), "radius": 10.0, "height": 28.0}


func receive_impact(direction: Vector2, _impulse: float, _recovery: float = 0.0) -> void:
	if not direction.is_zero_approx():
		last_hit_direction = direction.normalized()


func take_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_flash_remaining = 0.12
	_flash_material.set_shader_parameter(&"flash_amount", 1.0)
	if health <= 0.0:
		_stop()
		var fade: Tween = create_tween()
		fade.tween_property(self, "modulate:a", 0.0, 0.18)
		fade.tween_callback(queue_free)
		defeated.emit()


func _player_center() -> Vector2:
	return player.surface_world_position() - Vector2(0, 5)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.dead or player.intro_locked:
		return
	_age += delta
	_phase_age += delta
	var subject: Vector2 = _player_center()
	_step_wave(subject, delta)
	if not is_alive() or player.dead:
		return
	var offset: Vector2 = subject - global_position
	match phase:
		Phase.HOVER:
			var inward: Vector2 = offset.normalized()
			var approach: float = clampf((offset.length() - 88.0) / 30.0, -1.0, 1.0)
			var desired: Vector2 = (inward * approach + inward.orthogonal() * _side * 0.48).limit_length(1.0)
			_drift = _drift.move_toward(desired * 84.0, 205.0 * delta)
			global_position += _drift * delta
			art.frame = int(_age / 0.14) % 4
			_cooldown -= delta
			if _cooldown <= 0.0 and not _wave_live and offset.length() <= ATTACK_DISTANCE:
				_gap_angle = offset.angle() + _side * 0.64
				phase = Phase.WINDUP
				_phase_age = 0.0
				art.frame = 4
		Phase.WINDUP:
			# Let the bell drift to a stop as the clapper swings back.
			_drift = _drift.move_toward(Vector2.ZERO, 320.0 * delta)
			global_position += _drift * delta
			var frame: int = _frame_at(_phase_age, WINDUP_FRAMES)
			if frame < 4:
				art.frame = 4 + frame
			else:
				phase = Phase.RING
				_phase_age = 0.0
				art.frame = 8
				_wave_origin = global_position
				_wave_radius = 12.0
				_wave_hit = false
				_wave_live = true
		Phase.RING:
			var frame: int = _frame_at(_phase_age, RELEASE_FRAMES)
			if frame < 4:
				art.frame = 8 + frame
			else:
				phase = Phase.HOVER
				_phase_age = 0.0
				_cooldown = 1.65
				_side = -_side
	_previous_subject = subject
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	_flash_material.set_shader_parameter(&"flash_amount", clampf(_flash_remaining * 14.0, 0.0, 1.0))
	queue_redraw()


func _frame_at(elapsed: float, durations: Array[float]) -> int:
	for index: int in range(durations.size()):
		elapsed -= durations[index]
		if elapsed < 0.0:
			return index
	return durations.size()


func _step_wave(subject: Vector2, delta: float) -> void:
	if not _wave_live:
		return
	var before: float = _previous_subject.distance_to(_wave_origin) - _wave_radius
	_wave_radius = minf(_wave_radius + WAVE_SPEED * delta, WAVE_RANGE)
	var after: float = subject.distance_to(_wave_origin) - _wave_radius
	if not _wave_hit and minf(before, after) <= WAVE_HALF_WIDTH and maxf(before, after) >= -WAVE_HALF_WIDTH:
		var offset: Vector2 = subject - _wave_origin
		if absf(angle_difference(_gap_angle, offset.angle())) > GAP_HALF_ANGLE:
			_wave_hit = player.receive_projectile_damage(DAMAGE, self)
	if _wave_radius >= WAVE_RANGE:
		_wave_live = false


func _draw() -> void:
	draw_set_transform(Vector2(0, 16), 0.0, Vector2(1.0, 0.43))
	draw_circle(Vector2.ZERO, 10.0, Color(0.10, 0.06, 0.13, 0.38))
	draw_set_transform(Vector2.ZERO)
	var arc_begin: float = _gap_angle + GAP_HALF_ANGLE
	var arc_end: float = _gap_angle + TAU - GAP_HALF_ANGLE
	if phase == Phase.WINDUP:
		draw_arc(Vector2.ZERO, 22.0, arc_begin, arc_end, 36, Color(0.93, 0.63, 0.35, 0.55), 1.0)
	if _wave_live:
		var alpha: float = 1.0 - smoothstep(WAVE_RANGE - 24.0, WAVE_RANGE, _wave_radius)
		var center: Vector2 = to_local(_wave_origin)
		draw_arc(center, _wave_radius, arc_begin, arc_end, 64, Color(0.53, 0.29, 0.52, alpha * 0.66), 5.0)
		draw_arc(center, _wave_radius + 1.0, arc_begin, arc_end, 64, Color(1.0, 0.76, 0.46, alpha * 0.92), 2.0)


func _stop() -> void:
	_wave_live = false
	set_physics_process(false)
	remove_from_group(&"enemy_bodies")
	remove_from_group(&"bone_bells")
	queue_redraw()


func dismiss() -> void:
	_stop()
	queue_free()
