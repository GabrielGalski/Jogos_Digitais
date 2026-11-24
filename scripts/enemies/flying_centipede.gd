extends Node2D
## Flight is in the visual plane. Joints follow the distance traveled by the head.
signal defeated

const SEGMENT: Script = preload("res://scripts/enemies/flying_centipede_segment.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const ATLAS: Texture2D = preload("res://assets/enemies/flying_centipede/spritesheet.png")
const SFX: Script = preload("res://scripts/audio/horde_audio.gd")
const CHEWING: AudioStream = preload("res://assets/audio/enemies/elite/flying_centipede/approach_loop.wav")
const HIT_PLAYER: AudioStream = preload("res://assets/audio/enemies/elite/flying_centipede/hit_player.wav")
const DEFEAT: AudioStream = preload("res://assets/audio/enemies/elite/flying_centipede/defeat.wav")
const CHEW_RANGE: float = 235.0
const SEGMENT_COUNT: int = 8
const NECK_SPACING: float = 17.0
const BODY_SPACING: float = 14.0
const HOVER_HEIGHT: float = 14.0
const ORBIT_RADIUS: float = 114.0
const ORBIT_SPEED: float = 148.0
const COVER_RADIUS_LIMIT: float = 155.0
const DIVE_SPEED: float = 172.0
const CHARGE_SPEED: float = 224.0
const RETREAT_SPEED: float = 164.0
const CONTACT_DAMAGE: int = 6

enum Flight { CIRCLE, DIVE, CHARGE, RETREAT }

var player: Player
var sfx: SFX
var entry_heading: Vector2 = Vector2.RIGHT
var entry_distance: float = 175.0
var arena_origin: Vector2
var horde_members: Array[Node2D] = []
var flight: Flight = Flight.CIRCLE
var segments: Array[SEGMENT] = []
var head: Sprite2D
var tail: Sprite2D
var _heading: Vector2
var _speed: float = ORBIT_SPEED
var _orbit_radius: float = ORBIT_RADIUS
var _cover_radius: float = ORBIT_RADIUS
var _cover_refresh: float = 0.0
var _orbit_turn: float = 0.0
var _orbit_target: float = TAU * 1.5
var _turn_side: float = 1.0
var _trail: PackedVector2Array = PackedVector2Array()
var _previous_subject: Vector2
var _charge_distance: float = 0.0
var _charge_aim: Vector2
var _retreat_distance: float = 0.0
var _age: float = 0.0
var _contact_spent: bool = false
var _chewing: AudioStreamPlayer2D


func _ready() -> void:
	add_to_group(&"flying_centipedes")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 1
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_heading = entry_heading
	_turn_side = -1.0 if entry_heading.x < 0.0 else 1.0
	_previous_subject = _player_center()
	head = _new_art(0)
	add_child(head)
	head.position = _previous_subject - _heading * entry_distance
	_chewing = AudioStreamPlayer2D.new()
	_chewing.stream = CHEWING
	_chewing.bus = SFX.ELITE_BUS
	_chewing.max_distance = SFX.ELITE_RANGE
	_chewing.attenuation = 0.0
	_chewing.volume_db = -60.0
	head.add_child(_chewing)
	_chewing.play()
	for index: int in range(SEGMENT_COUNT):
		var segment: SEGMENT = SEGMENT.new()
		segment.name = "Segment_%d" % (index + 1)
		segment.art = _new_art(1)
		segment.add_child(segment.art)
		segment.broken.connect(_on_segment_broken)
		add_child(segment)
		segments.append(segment)
	tail = _new_art(2)
	add_child(tail)
	_trail.append(head.position - _heading * (NECK_SPACING + BODY_SPACING * (SEGMENT_COUNT + 1)))
	_trail.append(head.position)
	_update_joints()


func _new_art(row: int) -> Sprite2D:
	var art: Sprite2D = Sprite2D.new()
	art.texture = ATLAS
	art.hframes = 4
	art.vframes = 3
	art.frame_coords = Vector2i(0, row)
	art.z_index = 5
	return art


func _player_center() -> Vector2:
	return to_local(player.surface_world_position()) - Vector2(0, 5)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.dead or player.intro_locked:
		return
	for segment: SEGMENT in segments:
		if segment.is_in_group(&"immobilized_enemies"):
			return
	var subject: Vector2 = _player_center()
	var charging: bool = flight == Flight.CHARGE
	var before: PackedVector2Array = PackedVector2Array()
	if charging and not _contact_spent:
		before = _part_positions()
	_age += delta
	var aim: Vector2 = head.position.direction_to(subject)
	var distance: float = head.position.distance_to(subject)
	var orbit_center: Vector2 = to_local(arena_origin) + Vector2(0, player.floor_visual_offset().y)
	orbit_center = orbit_center.lerp(subject, 0.78)
	var radial: Vector2 = head.position - orbit_center
	var outward: Vector2 = radial.normalized() if not radial.is_zero_approx() else _heading
	var tangent: Vector2 = outward.orthogonal() * _turn_side
	if flight == Flight.CIRCLE or flight == Flight.RETREAT:
		_cover_refresh -= delta
		if _cover_refresh <= 0.0:
			_cover_refresh = 0.15
			var look_ahead: Vector2 = (outward + tangent * 0.30).normalized()
			_cover_radius = _radius_behind_horde(orbit_center, look_ahead)
		_orbit_radius = move_toward(_orbit_radius, _cover_radius, 46.0 * delta)
	var radius: float = _orbit_radius + sin(_age * 1.65) * 12.0
	var next_speed: float = ORBIT_SPEED
	match flight:
		Flight.CIRCLE:
			next_speed = ORBIT_SPEED * minf(_orbit_radius / ORBIT_RADIUS, 1.25)
			var correction: float = clampf((radius - radial.length()) / 42.0, -2.5, 2.0)
			_turn((tangent + outward * correction).normalized(), 3.9 * delta)
			if absf(radius - radial.length()) < 34.0:
				_orbit_turn += maxf(_heading.dot(tangent), 0.0) * _speed * delta / radius
			if _orbit_turn >= _orbit_target:
				flight = Flight.DIVE
		Flight.DIVE:
			next_speed = DIVE_SPEED
			_turn(aim, 4.8 * delta)
			if distance <= 95.0 and not aim.is_zero_approx() and absf(_heading.angle_to(aim)) < 0.24:
				flight = Flight.CHARGE
				_charge_aim = aim
				_charge_distance = distance + 55.0
				_contact_spent = false
		Flight.CHARGE:
			next_speed = CHARGE_SPEED
			_turn(_charge_aim, 4.0 * delta)
			_charge_distance -= _speed * delta
			if _charge_distance <= 0.0:
				flight = Flight.RETREAT
				_retreat_distance = 0.0
				_cover_refresh = 0.0
		Flight.RETREAT:
			next_speed = RETREAT_SPEED
			_turn((outward + tangent * 0.85).normalized(), 3.2 * delta)
			_retreat_distance += _speed * delta
			if radial.length() >= radius + 22.0 or _retreat_distance >= 130.0:
				flight = Flight.CIRCLE
				_orbit_target = TAU
				_orbit_turn = 0.0
	_speed = move_toward(_speed, next_speed, 240.0 * delta)
	head.position += _heading * _speed * delta
	_update_chewing(delta, head.position.distance_to(subject))
	_trail.append(head.position)
	_update_joints()
	if not before.is_empty():
		_check_charge_contact(before, subject)
	_previous_subject = subject
	queue_redraw()


func _update_chewing(delta: float, distance: float) -> void:
	var proximity: float = 1.0 - smoothstep(22.0, CHEW_RANGE, distance)
	var volume: float = linear_to_db(maxf(0.001, proximity * db_to_linear(-5.0)))
	var pace: float = 1.35 if flight in [Flight.DIVE, Flight.CHARGE] else 0.90
	_chewing.volume_db = lerpf(_chewing.volume_db, volume, 1.0 - exp(-18.0 * delta))
	_chewing.pitch_scale = move_toward(_chewing.pitch_scale, pace, delta * 2.5)
	if is_instance_valid(sfx) and _chewing.volume_db > -30.0:
		sfx.feature_elite(head.global_position, 0.12, CHEW_RANGE)


func _turn(towards: Vector2, max_radians: float) -> void:
	if not towards.is_zero_approx():
		_heading = _heading.rotated(clampf(_heading.angle_to(towards), -max_radians, max_radians))


func _radius_behind_horde(center: Vector2, outward: Vector2) -> float:
	var radius: float = ORBIT_RADIUS
	for actor: Node2D in horde_members:
		if not is_instance_valid(actor):
			continue
		var offset: Vector2 = to_local(CONTACTS.damage_center(actor)) - center
		var depth: float = offset.dot(outward)
		if depth > 0.0 and absf(offset.cross(outward)) <= depth * 0.68 and offset.length_squared() <= COVER_RADIUS_LIMIT * COVER_RADIUS_LIMIT:
			radius = maxf(radius, minf(depth + 24.0, COVER_RADIUS_LIMIT))
	return radius


func _update_joints() -> void:
	head.rotation = _heading.angle() + PI * 0.5
	var frame: int = int(_age * 12.0) % 4
	head.frame_coords.x = 2 if flight == Flight.CHARGE else frame % 2
	var cursor: int = _trail.size() - 1
	var distance_walked: float = 0.0
	for index: int in range(segments.size() + 1):
		var offset: float = NECK_SPACING + BODY_SPACING * index
		while cursor > 1:
			var edge: float = _trail[cursor].distance_to(_trail[cursor - 1])
			if distance_walked + edge >= offset:
				break
			distance_walked += edge
			cursor -= 1
		var front: Vector2 = _trail[cursor]
		var rear: Vector2 = _trail[cursor - 1]
		var joint: Node2D = tail as Node2D if index == segments.size() else segments[index] as Node2D
		var fraction: float = clampf((offset - distance_walked) / maxf(front.distance_to(rear), 0.001), 0.0, 1.0)
		joint.position = front.lerp(rear, fraction)
		joint.rotation = rear.angle_to_point(front) + PI * 0.5
		var art: Sprite2D = tail if joint == tail else segments[index].art
		art.frame_coords.x = posmod(frame - index, 4)
	if cursor > 1:
		_trail = _trail.slice(cursor - 1)


func _part_positions() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([head.position])
	for segment: SEGMENT in segments:
		points.append(segment.position)
	points.append(tail.position)
	return points


func _check_charge_contact(before: PackedVector2Array, subject: Vector2) -> void:
	if player.is_dashing() or player.mutation_invisible:
		return
	var after: PackedVector2Array = _part_positions()
	for index: int in range(after.size()):
		var hit: Dictionary = CONTACTS.capsule_hit(before[index] - _previous_subject, after[index] - subject,
			Vector2.ZERO, 11.0 if index == 0 else 9.0, 0.0)
		if hit.is_empty():
			continue
		_contact_spent = true
		# Redirect a parry of the head or tail to the adjacent vulnerable joint.
		var joint: SEGMENT = segments[clampi(index - 1, 0, segments.size() - 1)]
		if not player.try_parry_enemy_attack(joint, player.global_position):
			var health_before: float = player.health
			player.receive_contact_damage(CONTACT_DAMAGE, _heading, 80.0, self)
			if player.health < health_before and is_instance_valid(sfx):
				sfx.play_elite(HIT_PLAYER, player.surface_world_position(), 2.0)
		return


func _on_segment_broken(part: Node2D) -> void:
	var segment: SEGMENT = part as SEGMENT
	segments.erase(segment)
	if not segments.is_empty():
		return
	segment.final_segment = true
	set_physics_process(false)
	_chewing.stop()
	if is_instance_valid(sfx):
		sfx.play_elite(DEFEAT, head.global_position, 3.0)
	remove_from_group(&"flying_centipedes")
	head.modulate = Color(1.25, 1.15, 1.0)
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.18)
	fade.tween_callback(queue_free)
	defeated.emit()


func dismiss() -> void:
	set_physics_process(false)
	if _chewing != null:
		_chewing.stop()
	for segment: SEGMENT in segments:
		segment.remove_from_group(&"enemy_bodies")
		segment.health = 0.0
	queue_free()


func _draw() -> void:
	if head == null:
		return
	for point: Vector2 in _part_positions():
		draw_set_transform((point + Vector2(0, HOVER_HEIGHT)).round(), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 8.0, Color(0.10, 0.06, 0.13, 0.38))
	draw_set_transform(Vector2.ZERO)
