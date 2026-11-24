extends Node2D
## A floating miniboss. Warm rings announce a volley of three broken sound waves.
signal defeated

const ATLAS: Texture2D = preload("res://assets/enemies/bone_bell/spritesheet.png")
const FLASH: Shader = preload("res://shaders/white_damage_flash.gdshader")
const CHIME: AudioStream = preload("res://assets/enemies/bone_bell/chime.wav")
const HIT_PLAYER: AudioStream = preload("res://assets/audio/enemies/elite/bone_bell/hit_player.wav")
const DEFEAT: AudioStream = preload("res://assets/audio/enemies/elite/bone_bell/defeat.wav")
const SFX: Script = preload("res://scripts/audio/horde_audio.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const WINDUP_FRAMES: Array[float] = [0.25, 0.21, 0.16, 0.12]
const WINDUP_TIME: float = 0.74
const WARNING_BEATS: Array[float] = [0.0, 0.25, 0.46]
const PULSE_BEATS: Array[float] = [0.0, 0.34, 0.68]
const WARNING: Script = preload("res://scripts/visual/booster_exclamation.gd")
const ATTACK_DISTANCE: float = 116.0
const RETREAT_COOLDOWN: float = 2.1
const FIELD_RADIUS: float = 31.0
const WAVE_SPEED: float = 192.0
const WAVE_RANGE: float = 198.0
const WAVE_HALF_WIDTH: float = 4.0
const GAP_CENTERS: Array[float] = [0.70, PI, TAU - 0.70]
const GAP_HALF_ANGLE: float = 0.27
const DAMAGE: int = 6
const MAX_HEALTH: float = 30.0

enum Phase { HOVER, WINDUP, RING, RETREAT }

class Pulse:
	var age: float = 0.0
	var hit_player: bool = false

var player: Player
var sfx: SFX
var horde_members: Array[Node2D] = []
var health: float = MAX_HEALTH
var last_hit_direction: Vector2 = Vector2.DOWN
var phase: Phase = Phase.HOVER
var art: Sprite2D
var _warning: AnimatedSprite2D
var _chime: AudioStreamPlayer2D
var _flash_material: ShaderMaterial
var _flash_remaining: float = 0.0
var _drift: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _phase_age: float = 0.0
var _side: float = 1.0
var _attack_angle: float = 0.0
var _beats_played: int = 0
var _pulses: Array[Pulse] = []
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
	_warning = WARNING.warning_sprite(get_tree())
	_warning.position.y = -25.0
	_warning.z_index = art.z_index + 1
	_warning.hide()
	add_child(_warning)
	_chime = AudioStreamPlayer2D.new()
	_chime.stream = CHIME
	_chime.max_polyphony = 3
	_chime.bus = SFX.ELITE_BUS
	_chime.max_distance = SFX.ELITE_RANGE
	add_child(_chime)
	_previous_subject = _player_center()


func is_alive() -> bool:
	return health > 0.0 and not is_queued_for_deletion()


func get_current_health() -> float:
	return health


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": Vector2(0, -2), "radius": 10.0, "height": 28.0}


func sound_field_radius() -> float:
	return FIELD_RADIUS


func receive_impact(direction: Vector2, _impulse: float, _recovery: float = 0.0) -> void:
	if not direction.is_zero_approx():
		last_hit_direction = direction.normalized()


func take_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0 or is_in_group(&"sound_fields"):
		return
	health = maxf(health - amount, 0.0)
	_flash_remaining = 0.12
	_flash_material.set_shader_parameter(&"flash_amount", 1.0)
	if health <= 0.0:
		_stop()
		if is_instance_valid(sfx):
			sfx.play_elite(DEFEAT, global_position, 3.0)
		var fade: Tween = create_tween()
		fade.tween_property(self, "modulate:a", 0.0, 0.18)
		fade.tween_callback(queue_free)
		defeated.emit()


func _player_center() -> Vector2:
	return player.surface_world_position() - Vector2(0, 5)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.dead or player.intro_locked or is_in_group(&"immobilized_enemies"):
		return
	_age += delta
	_phase_age += delta
	var subject: Vector2 = _player_center()
	var offset: Vector2 = subject - global_position
	match phase:
		Phase.HOVER:
			var inward: Vector2 = offset.normalized()
			var approach: float = clampf((offset.length() - 88.0) / 30.0, -1.0, 1.0)
			var desired: Vector2 = (inward * approach + inward.orthogonal() * _side * 0.48).limit_length(1.0)
			_drift = _drift.move_toward(desired * 84.0, 205.0 * delta)
			global_position += _drift * delta
			art.frame = int(_age / 0.14) % 4
			if _age >= 0.4 and offset.length() <= ATTACK_DISTANCE:
				_drift = Vector2.ZERO
				_attack_angle = global_position.angle_to_point(subject)
				phase = Phase.WINDUP
				_phase_age = 0.0
				_beats_played = 0
				art.frame = 4
				_warning.show()
				_warning.play(&"idle")
				add_to_group(&"sound_fields")
				_play_warning_beats()
		Phase.WINDUP:
			art.frame = 4 + mini(_frame_at(_phase_age, WINDUP_FRAMES), 3)
			_play_warning_beats()
			if _phase_age >= WINDUP_TIME:
				_warning.hide()
				_warning.stop()
				phase = Phase.RING
				_phase_age = 0.0
				_beats_played = 0
				_release_ready_pulses()
		Phase.RING:
			_advance_pulses(subject, delta)
			_release_ready_pulses()
			if _beats_played == PULSE_BEATS.size() and _pulses.is_empty():
				remove_from_group(&"sound_fields")
				phase = Phase.RETREAT
				_phase_age = 0.0
				_side = -_side
		Phase.RETREAT:
			var goal: Vector2 = _cover_position(subject)
			var desired: Vector2 = ((goal - global_position) * 3.0).limit_length(96.0)
			_drift = _drift.move_toward(desired, 240.0 * delta)
			global_position += _drift * delta
			art.frame = int(_age / 0.14) % 4
			if _phase_age >= RETREAT_COOLDOWN:
				phase = Phase.HOVER
				_phase_age = 0.0
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


func _play_warning_beats() -> void:
	while _beats_played < WARNING_BEATS.size() and _phase_age >= WARNING_BEATS[_beats_played]:
		_play_chime(0.82 + 0.10 * _beats_played, -10.0)
		_beats_played += 1


func _release_ready_pulses() -> void:
	while _beats_played < PULSE_BEATS.size() and _phase_age >= PULSE_BEATS[_beats_played]:
		_pulses.append(Pulse.new())
		_play_chime(1.06 - 0.06 * _beats_played, -4.5)
		_beats_played += 1
	var since_beat: float = _phase_age - PULSE_BEATS[_beats_played - 1]
	art.frame = 8 + mini(int(since_beat * 14.0), 3)


func _play_chime(pitch: float, volume: float) -> void:
	_chime.pitch_scale = pitch
	_chime.volume_db = volume
	_chime.play()
	if is_instance_valid(sfx):
		sfx.feature_elite(global_position, CHIME.get_length() / pitch)


func _advance_pulses(subject: Vector2, delta: float) -> void:
	var previous: Vector2 = _previous_subject - global_position
	var current: Vector2 = subject - global_position
	for index: int in range(_pulses.size() - 1, -1, -1):
		var pulse: Pulse = _pulses[index]
		var before: float = previous.length() - _wave_radius(_expansion(pulse.age), pulse.age, previous.angle())
		pulse.age += delta
		var expanded: float = _expansion(pulse.age)
		var after: float = current.length() - _wave_radius(expanded, pulse.age, current.angle())
		if not pulse.hit_player and minf(before, after) <= WAVE_HALF_WIDTH and maxf(before, after) >= -WAVE_HALF_WIDTH:
			var crossing: float = clampf(before / (before - after), 0.0, 1.0) if not is_equal_approx(before, after) else 1.0
			if not _in_gap(previous.lerp(current, crossing).angle()):
				var health_before: float = player.health
				pulse.hit_player = player.receive_projectile_damage(DAMAGE, self)
				if player.health < health_before and is_instance_valid(sfx):
					sfx.play_elite(HIT_PLAYER, player.surface_world_position(), 2.0)
		if expanded >= WAVE_RANGE:
			_pulses.remove_at(index)


func _in_gap(angle: float) -> bool:
	for center: float in GAP_CENTERS:
		if absf(angle_difference(angle, _attack_angle + center)) <= GAP_HALF_ANGLE:
			return true
	return false


func _cover_position(subject: Vector2) -> Vector2:
	var outward: Vector2 = subject.direction_to(global_position)
	var goal: Vector2 = subject + outward.rotated(_side * 0.30) * 130.0
	var best: float = INF
	for actor: Node2D in horde_members:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.is_in_group(&"controlled_monsters"):
			continue
		var center: Vector2 = CONTACTS.damage_center(actor)
		var offset: Vector2 = center - subject
		var distance: float = offset.length()
		if distance < 32.0 or distance > 146.0:
			continue
		var behind: Vector2 = center + offset.normalized() * 32.0
		var score: float = global_position.distance_to(behind) + absf(88.0 - distance) * 0.50
		if score < best:
			best = score
			goal = behind
	return goal


func _expansion(age: float) -> float:
	return 13.0 + age * WAVE_SPEED + sin(age * TAU * 2.4) * 2.6


func _wave_radius(radius: float, age: float, angle: float) -> float:
	return radius + sin(angle * 7.0 - age * 17.0) * 1.4 + sin(angle * 12.0 + age * 22.0) * 0.65


func _draw() -> void:
	draw_set_transform(Vector2(0, 16), 0.0, Vector2(1.0, 0.43))
	draw_circle(Vector2.ZERO, 10.0, Color(0.10, 0.06, 0.13, 0.38))
	draw_set_transform(Vector2.ZERO)
	if is_in_group(&"sound_fields"):
		draw_circle(Vector2.ZERO, FIELD_RADIUS, Color(0.89, 0.50, 0.22, 0.06))
		draw_arc(Vector2.ZERO, FIELD_RADIUS, 0.0, TAU, 45, Color(0.95, 0.66, 0.34, 0.43), 1.0)
	for pulse: Pulse in _pulses:
		var radius: float = _expansion(pulse.age)
		var opacity: float = 1.0 - smoothstep(WAVE_RANGE - 20.0, WAVE_RANGE, radius)
		_draw_broken_ring(radius, pulse.age, Color("#ff6b69"), opacity)


func _draw_broken_ring(radius: float, age: float, tint: Color, opacity: float) -> void:
	for index: int in range(GAP_CENTERS.size()):
		var begin: float = _attack_angle + GAP_CENTERS[index] + GAP_HALF_ANGLE
		var next: float = GAP_CENTERS[index + 1] if index + 1 < GAP_CENTERS.size() else GAP_CENTERS[0] + TAU
		var end: float = _attack_angle + next - GAP_HALF_ANGLE
		_draw_ring(radius, age, begin, end, tint, opacity)


func _draw_ring(radius: float, age: float, begin: float, end: float, tint: Color, opacity: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(8, ceili((end - begin) * maxf(radius, 20.0) / 4.0))
	points.resize(count + 1)
	for index: int in range(count + 1):
		var angle: float = lerpf(begin, end, float(index) / count)
		points[index] = Vector2.from_angle(angle) * _wave_radius(radius, age, angle)
	draw_polyline(points, Color(tint, opacity * 0.24), 4.0)
	draw_polyline(points, Color(tint, opacity), 1.4)


func _stop() -> void:
	_warning.hide()
	_warning.stop()
	_pulses.clear()
	if is_in_group(&"sound_fields"):
		remove_from_group(&"sound_fields")
	_chime.stop()
	set_physics_process(false)
	remove_from_group(&"enemy_bodies")
	remove_from_group(&"bone_bells")
	queue_redraw()


func dismiss() -> void:
	_stop()
	queue_free()
