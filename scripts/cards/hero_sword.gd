extends Node2D
## A companion that hunts independently within a leash around the caster.

const FRAMES: SpriteFrames = preload("res://resources/visual/hero_sword_frames.tres")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const AFFILIATION: Script = preload("res://scripts/combat/combat_affiliation.gd")
const STAB_RADIUS: float = 60.0
const CUT_RADIUS: float = 32.0
const LONGCUT_RADIUS: float = 46.0
const SEARCH_RADIUS: float = 96.0
const LEASH_RADIUS: float = 112.0
const HOVER_DISTANCE: float = 30.0
const PURSUE_SPEED: float = 176.0
const RETURN_SPEED: float = 140.0
const SEARCH_INTERVAL: float = 0.15
const RING_DURATION: float = 0.16

var player: Player
var effects: CombatEffects
var _sprite: AnimatedSprite2D
var _move: StringName = &"idle"
var _frame: int = 0
var _hit_frame: int = 0
var _age: float = 0.0
var _idle_age: float = 0.0
var _search_remaining: float = 0.0
var _recovery_remaining: float = 0.0
var _side: float = 1.0
var _target: Node2D
var _direction: Vector2 = Vector2.RIGHT
var _reach: float = 0.0
var _damage: float = 0.0
var _recovery: float = 0.0
var _ring_time: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * 0.8
	add_child(_sprite)
	_idle_pose(0.0)
	global_position = _home_position()


func advance(delta: float) -> void:
	z_index = player.z_index + 1
	var from_player: float = global_position.distance_squared_to(player.surface_world_position())
	if from_player > LEASH_RADIUS * LEASH_RADIUS:
		_move = &"idle"
		_target = null
		_ring_time = 0.0
		queue_redraw()
		if from_player > 4.0 * LEASH_RADIUS * LEASH_RADIUS:
			global_position = _home_position()
		else:
			_idle_pose(delta)
			global_position = global_position.move_toward(_home_position(), RETURN_SPEED * delta)
			return
	if _ring_time > 0.0:
		_ring_time = maxf(0.0, _ring_time - delta)
		queue_redraw()
	if _move == &"idle":
		_fly(delta)
		return
	_age += delta
	var duration: float = FRAMES.get_frame_count(_move) / FRAMES.get_animation_speed(_move)
	var previous: int = _frame
	_frame = mini(floori(_age * FRAMES.get_animation_speed(_move)), FRAMES.get_frame_count(_move) - 1)
	_sprite.frame = _frame
	var travel: float = sin(PI * clampf(_age / duration, 0.0, 1.0))
	_sprite.position = (_direction * (14.0 + travel * (15.0 if _move == &"stab" else 5.0)) - Vector2(0, 5)).round()
	if previous < _hit_frame and _frame >= _hit_frame:
		_strike()
	if _age >= duration:
		_recovery_remaining = _recovery
		_move = &"idle"
		_idle_pose(0.0)


func _idle_pose(delta: float) -> void:
	_idle_age += delta
	if absf(player.body.facing.x) > 0.25:
		_side = signf(player.body.facing.x)
	_sprite.animation = &"idle"
	_sprite.offset = -Vector2(13, 19)
	_sprite.rotation = 0.0
	_sprite.position = Vector2(0.0, roundf(sin(_idle_age * 4.0) * 2.0))


func _home_position() -> Vector2:
	return player.surface_world_position() + Vector2(HOVER_DISTANCE * _side, -12.0)


func _fly(delta: float) -> void:
	_idle_pose(delta)
	_recovery_remaining = maxf(0.0, _recovery_remaining - delta)
	_search_remaining -= delta
	var caster: Vector2 = player.surface_world_position()
	if is_instance_valid(_target) and (not _available(_target, caster, LEASH_RADIUS) or not _line_clear(CONTACTS.damage_center(_target))):
		_target = null
	if not is_instance_valid(_target) and _search_remaining <= 0.0:
		_search_remaining = SEARCH_INTERVAL
		_target = _seek(caster)
	if not is_instance_valid(_target):
		global_position = global_position.move_toward(_home_position(), RETURN_SPEED * delta)
		return
	var center: Vector2 = CONTACTS.damage_center(_target)
	var distant: bool = caster.distance_squared_to(center) > LONGCUT_RADIUS * LONGCUT_RADIUS
	var approach: float = 36.0 if distant else 22.0
	var offset: Vector2 = center - global_position
	if offset.length_squared() > (approach + 0.5) * (approach + 0.5):
		var goal: Vector2 = center - offset.normalized() * approach
		global_position = global_position.move_toward(goal, PURSUE_SPEED * delta)
		return
	if _recovery_remaining > 0.0:
		return
	_direction = offset.normalized()
	if _direction.is_zero_approx():
		_direction = Vector2(_side, 0)
	if _has_crowd():
		_begin(&"longcut", Vector2(8, 19), 4, LONGCUT_RADIUS, 6.0, 0.65)
	elif distant:
		_begin(&"stab", Vector2(9, 5), 2, STAB_RADIUS, 7.0, 0.45)
	else:
		_begin(&"cut", Vector2(8, 22), 3, CUT_RADIUS, 4.0, 0.35)


func _seek(caster: Vector2) -> Node2D:
	var closest: Node2D
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = node as Node2D
		if not _available(enemy, caster, SEARCH_RADIUS):
			continue
		var center: Vector2 = CONTACTS.damage_center(enemy)
		var distance: float = global_position.distance_squared_to(center)
		if distance < best_distance and _line_clear(center):
			closest = enemy
			best_distance = distance
	return closest


func _has_crowd() -> bool:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		if _can_reach(node as Node2D, LONGCUT_RADIUS):
			count += 1
			if count == 3:
				return true
	return false


func _begin(move: StringName, pivot: Vector2, strike_frame: int, radius: float, damage: float, recovery: float) -> void:
	_move = move
	_hit_frame = strike_frame
	_reach = radius
	_damage = damage
	_recovery = recovery
	_age = 0.0
	_frame = 0
	_sprite.animation = move
	_sprite.frame = 0
	_sprite.offset = -pivot
	_sprite.rotation = _direction.angle()
	_sprite.position = (_direction * 14.0 - Vector2(0, 5)).round()


func _strike() -> void:
	if _move == &"stab":
		if is_instance_valid(_target) and _can_reach(_target, _reach):
			_hit(_target)
		return
	for node: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		if not is_instance_valid(node):
			continue
		var enemy: Node2D = node as Node2D
		if _can_reach(enemy, _reach):
			_hit(enemy)
	_ring_time = RING_DURATION
	queue_redraw()


func _can_reach(enemy: Node2D, radius: float) -> bool:
	if not _available(enemy, player.surface_world_position(), LEASH_RADIUS):
		return false
	var center: Vector2 = CONTACTS.damage_center(enemy)
	return global_position.distance_squared_to(center) <= radius * radius and _line_clear(center)


func _available(enemy: Node2D, center: Vector2, radius: float) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return false
	if center.distance_squared_to(CONTACTS.damage_center(enemy)) > radius * radius:
		return false
	if enemy.is_in_group(&"sound_fields") or not AFFILIATION.can_damage(AFFILIATION.PLAYER, enemy):
		return false
	return enemy.has_method("is_alive") and bool(enemy.call("is_alive"))


func _line_clear(at: Vector2) -> bool:
	var line: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, at, 1)
	return get_world_2d().direct_space_state.intersect_ray(line).is_empty()


func _hit(enemy: Node2D) -> void:
	var direction: Vector2 = global_position.direction_to(CONTACTS.damage_center(enemy))
	effects.apply_hit(enemy, _damage, direction, 0.0)


func _draw() -> void:
	if _ring_time <= 0.0:
		return
	var strength: float = _ring_time / RING_DURATION
	for index: int in range(6):
		var angle: float = TAU * float(index) / 6.0
		draw_arc(Vector2.ZERO, _reach, angle, angle + 0.65, 8, Color(1.0, 0.79, 0.45, 0.48 * strength), 1.0)
