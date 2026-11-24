extends CharacterBody2D

signal health_changed(current: float, maximum: float)
signal defeated

const ART: Script = preload("res://scripts/bosses/vampire/vampire_art.gd")
const SERPENT: Script = preload("res://scripts/bosses/vampire/vampire_serpent.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const MARKER: Script = preload("res://scripts/visual/booster_exclamation.gd")

const PATTERNS: Array[Array] = [
	[0, 60, 120, 180, 240, 300],
	[15, 75, 135, 195, 255, 315],
	[0, 45, 135, 180, 225, 315],
]
const VOLLEY_TIMES: Array[float] = [0.48, 0.82, 1.16]
const WARNING_TIME: float = 0.82
const WARNING_IN: float = 0.12
const WARNING_OUT: float = 0.20
const RETURN_TIME: float = 0.40
const SMOKE_HOLD: float = 0.15
const RECOVERY_TIME: float = 1.0
const CLONE_START: float = 22.0
const DANGER_START: float = 56.0
const CLONE_SPEED: float = 345.0
const CLONE_RADIUS: float = 6.0
const CLONE_DAMAGE: int = 12
const VISUAL_SCALE: float = 1.35
const VISUAL_OFFSET: Vector2 = Vector2(0, -15)

enum Phase { WAITING, OPENING, SERPENTS, CLEAR_SERPENTS, WARNING, CHARGING, SMOKE, RECOVERY, FINISHED }

class ShadowLane:
	extends RefCounted
	var direction: Vector2
	var distance: float
	var sprite: AnimatedSprite2D
	var warning: AnimatedSprite2D
	var arrived: bool = false
	var hit_player: bool = false
	var smoke_age: float = 0.0

@export var max_health: float = 320.0
var health: float
var phase: Phase = Phase.WAITING
var wave: int = 0
var completed_patterns: int = 0
var _player: Player
var _player_shape: CollisionShape2D
var _player_capsule: CapsuleShape2D
var _attacks: Node2D
var _extent: Vector2
var _charge_speed: float = CLONE_SPEED
var _frames: SpriteFrames
var _warning_frames: SpriteFrames
var _sprite: AnimatedSprite2D
var _facing: String = "down"
var _elapsed: float = 0.0
var _next_volley: int = 0
var _pattern: PackedFloat32Array
var _lanes: Array[ShadowLane] = []
var _previous_feet: Vector2


func configure(player: Player, arena: Rect2, attacks: Node2D) -> void:
	_player = player
	_attacks = attacks
	_extent = arena.size * 0.5 - Vector2.ONE * 8.0
	_charge_speed = CLONE_SPEED * minf(arena.size.x, arena.size.y) / 416.0


func _ready() -> void:
	health = max_health
	set_meta(&"is_boss", true)
	add_to_group(&"boss_bodies")
	collision_layer = 0
	collision_mask = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_shape = _player.get_node("CollisionShape2D") as CollisionShape2D
	_player_capsule = _player_shape.shape as CapsuleShape2D
	_frames = ART.build_frames()
	_warning_frames = MARKER.marker_frames(get_tree(), true)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "VampireSprite"
	_sprite.sprite_frames = _frames
	_sprite.position = VISUAL_OFFSET
	_sprite.scale = Vector2.ONE * VISUAL_SCALE
	add_child(_sprite)
	_sprite.animation_finished.connect(_on_animation_finished)
	_play("idle")
	# Reflection uses the normal projectile collider; other player shots use the swept hurt capsule.
	var body_shape: CollisionShape2D = CollisionShape2D.new()
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = 15.0
	capsule.height = 38.0
	body_shape.shape = capsule
	body_shape.position = Vector2(0, -14)
	add_child(body_shape)


func begin() -> void:
	if phase != Phase.WAITING:
		return
	collision_layer = 4
	add_to_group(&"enemy_bodies")
	_enter(Phase.OPENING)


func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	if _player.dead:
		stop_attacks()
		return
	_elapsed += delta
	match phase:
		Phase.OPENING:
			_face_player()
			_play("idle")
			if _elapsed >= 0.68:
				_begin_serpents()
		Phase.SERPENTS:
			if _next_volley < VOLLEY_TIMES.size() and _elapsed >= VOLLEY_TIMES[_next_volley]:
				_fire_serpents(_next_volley)
				_next_volley += 1
			if _next_volley == VOLLEY_TIMES.size():
				_enter(Phase.CLEAR_SERPENTS)
		Phase.CLEAR_SERPENTS:
			if _elapsed >= 0.42 and _attacks.get_child_count() == 0:
				var pattern_count: int = PATTERNS.size() if health <= max_health * 0.5 else 2
				_pattern = PackedFloat32Array(PATTERNS[completed_patterns % pattern_count])
				_warn_wave(1)
		Phase.WARNING:
			if _elapsed >= WARNING_TIME:
				_start_charge()
			else:
				_update_warning()
		Phase.CHARGING:
			_advance_copies(delta)
		Phase.SMOKE:
			for lane: ShadowLane in _lanes:
				_advance_smoke(lane, delta)
			if _elapsed >= RETURN_TIME:
				_discard_copies()
				if wave == 1:
					_warn_wave(2)
				else:
					completed_patterns += 1
					_play("idle")
					_enter(Phase.RECOVERY)
		Phase.RECOVERY:
			if _elapsed >= RECOVERY_TIME:
				_begin_serpents()


func _enter(next_phase: Phase) -> void:
	phase = next_phase
	_elapsed = 0.0


func _face_player() -> void:
	_facing = ART.facing(global_position.direction_to(_player.global_position))


func _play(action: String) -> void:
	_sprite.play(StringName(action + "_" + _facing))


func _begin_serpents() -> void:
	_face_player()
	_play("attack")
	_next_volley = 0
	_enter(Phase.SERPENTS)


func _fire_serpents(volley: int) -> void:
	# Offset each salvo and fix its aim at release. The snakes never home afterward.
	var aim: Vector2 = global_position.direction_to(_player.global_position)
	if aim.is_zero_approx():
		aim = Vector2.DOWN
	var count: int = 6 if health <= max_health * 0.5 else 5
	var shift: float = [-7.0, 7.0, 0.0][volley]
	for index: int in range(count):
		var offset: float = (float(index) - float(count - 1) * 0.5) * 15.0 + shift
		var serpent: Node2D = SERPENT.new() as Node2D
		serpent.set("target", _player)
		serpent.set("shooter", self)
		serpent.set("direction", aim.rotated(deg_to_rad(offset)))
		serpent.set("speed", 120.0 + 4.0 * volley)
		serpent.set("wave_sign", 1.0 if (index + volley) % 2 == 0 else -1.0)
		serpent.set("radius", 3.7)
		serpent.set("damage", 6)
		serpent.set("remaining", 2.8)
		serpent.position = _attacks.to_local(global_position + aim * 16.0 + Vector2(0, -6))
		_attacks.add_child(serpent)


func _warn_wave(number: int) -> void:
	wave = number
	_face_player()
	_play("idle")
	_enter(Phase.WARNING)
	for index: int in range(_pattern.size()):
		var angle: float = _pattern[index]
		if wave == 2:
			var next: float = _pattern[index + 1] if index + 1 < _pattern.size() else _pattern[0] + 360.0
			angle = (angle + next) * 0.5
		var lane: ShadowLane = ShadowLane.new()
		lane.direction = Vector2.UP.rotated(deg_to_rad(angle))
		lane.distance = minf(_extent.x / maxf(0.001, absf(lane.direction.x)),
			_extent.y / maxf(0.001, absf(lane.direction.y)))
		lane.sprite = AnimatedSprite2D.new()
		lane.sprite.sprite_frames = _frames
		lane.sprite.position = lane.direction * CLONE_START + VISUAL_OFFSET
		lane.sprite.scale = Vector2.ONE * VISUAL_SCALE
		lane.sprite.modulate = Color(1.0, 0.67, 0.82, 0.66)
		lane.sprite.hide()
		add_child(lane.sprite)
		lane.warning = AnimatedSprite2D.new()
		lane.warning.name = "Warning_%02d" % (index + 1)
		lane.warning.sprite_frames = _warning_frames
		lane.warning.position = (lane.direction * (lane.distance * 0.61) + Vector2(0, -7)).round()
		lane.warning.scale = Vector2.ONE * 0.68
		lane.warning.z_index = 2
		lane.warning.modulate.a = 0.0
		add_child(lane.warning)
		lane.warning.play(&"idle")
		_lanes.append(lane)


func _update_warning() -> void:
	var fade_in: float = smoothstep(0.0, WARNING_IN, _elapsed)
	var fade_out: float = smoothstep(0.0, WARNING_OUT, WARNING_TIME - _elapsed)
	for lane: ShadowLane in _lanes:
		lane.warning.modulate.a = fade_in * fade_out


func _start_charge() -> void:
	_previous_feet = _player_shape.global_position
	_play("idle")
	for lane: ShadowLane in _lanes:
		lane.warning.hide()
		lane.warning.queue_free()
		lane.warning = null
		lane.sprite.show()
		lane.sprite.play(StringName("run_" + ART.facing(lane.direction)))
	_enter(Phase.CHARGING)


func _advance_copies(delta: float) -> void:
	var feet: Vector2 = _player_shape.global_position
	var all_arrived: bool = true
	var previous_distance: float = CLONE_START + maxf(0.0, _elapsed - delta) * _charge_speed
	var distance: float = CLONE_START + _elapsed * _charge_speed
	for lane: ShadowLane in _lanes:
		if lane.arrived:
			_advance_smoke(lane, delta)
			continue
		var end: float = minf(lane.distance, distance)
		lane.sprite.position = lane.direction * end + VISUAL_OFFSET
		if not lane.hit_player and end >= DANGER_START:
			var start: float = maxf(previous_distance, DANGER_START)
			var active_fraction: float = clampf((start - previous_distance) / maxf(distance - previous_distance, 0.001), 0.0, 1.0)
			var end_fraction: float = clampf((end - previous_distance) / maxf(distance - previous_distance, 0.001), 0.0, 1.0)
			var sweep: Dictionary = CONTACTS.capsule_hit(to_global(lane.direction * start) - _previous_feet.lerp(feet, active_fraction),
				to_global(lane.direction * end) - _previous_feet.lerp(feet, end_fraction), Vector2.ZERO,
				CLONE_RADIUS + _player_capsule.radius, _player_capsule.height * 0.5 - _player_capsule.radius)
			if not sweep.is_empty():
				lane.hit_player = _player.receive_projectile_damage(CLONE_DAMAGE, self)
		if end >= lane.distance:
			lane.arrived = true
			lane.sprite.modulate = Color(1.0, 0.83, 0.93, 0.78)
			lane.sprite.play(StringName("smoke_" + ART.facing(lane.direction)))
		else:
			all_arrived = false
	_previous_feet = feet
	if all_arrived:
		_enter(Phase.SMOKE)


func _advance_smoke(lane: ShadowLane, delta: float) -> void:
	lane.smoke_age += delta
	var progress: float = smoothstep(SMOKE_HOLD, RETURN_TIME, lane.smoke_age)
	lane.sprite.position = lane.direction * lane.distance * (1.0 - progress) + VISUAL_OFFSET
	lane.sprite.modulate.a = 0.78 * (1.0 - progress)


func _discard_copies() -> void:
	for lane: ShadowLane in _lanes:
		if is_instance_valid(lane.warning):
			lane.warning.hide()
			lane.warning.queue_free()
		lane.sprite.hide()
		lane.sprite.queue_free()
	_lanes.clear()


func stop_attacks() -> void:
	_discard_copies()
	for attack: Node in _attacks.get_children():
		attack.call("dismiss")
	collision_layer = 0
	remove_from_group(&"enemy_bodies")
	_enter(Phase.FINISHED)


func is_alive() -> bool:
	return phase != Phase.WAITING and phase != Phase.FINISHED


func get_current_health() -> float:
	return health


func get_combat_faction() -> StringName:
	return &"monsters"


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": Vector2(0, -14), "radius": 15.0, "height": 38.0}


func take_damage(amount: float) -> void:
	if not is_alive() or _player.dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		stop_attacks()
		_play("death")
		defeated.emit()
	elif phase in [Phase.CLEAR_SERPENTS, Phase.RECOVERY] and String(_sprite.animation).begins_with("idle"):
		_play("hurt")


func _on_animation_finished() -> void:
	var clip: String = String(_sprite.animation)
	if phase == Phase.FINISHED and clip.begins_with("death"):
		_sprite.hide()
	elif clip.begins_with("attack") or clip.begins_with("hurt"):
		_play("idle")
