class_name InsectActor
extends CharacterBody2D
## Shared damage/movement contract. Species decisions live in their own behaviors.
signal died(actor: Node2D)
signal damaged(amount: float, remaining_health: float)
signal attack_resolved(actor: Node2D, connected: bool)

const VISUAL: Script = preload("res://scripts/visual/insect_visual.gd")
const BRAINS: Dictionary[StringName, Script] = {
	&"tall": preload("res://scripts/enemies/insects/tall_behavior.gd"),
	&"fly": preload("res://scripts/enemies/insects/fly_behavior.gd"),
	&"little": preload("res://scripts/enemies/insects/little_behavior.gd"),
}
var profile: InsectProfile = null
var player: Player = null
var squad: Node2D = null
var remains_system: Node2D = null
var palette_variant: int = 0
var brain: RefCounted = null
var visual: AnimatedSprite2D = null
var neighbors: Array[Node2D] = []
var height_query: Callable = Callable()
var home_position: Vector2 = Vector2.ZERO
var floor_height: float = 0.0
var phase: float = 0.0
var orbit_sign: float = 1.0
var health: float = 0.0
var dying: bool = false
var engaged: bool = false
var suspended: bool = false
var desired_velocity: Vector2 = Vector2.ZERO
var hit_velocity: Vector2 = Vector2.ZERO
var attack_direction: Vector2 = Vector2.RIGHT
var attacks_started: int = 0
var hits_landed: int = 0
var _look: Vector2 = Vector2.RIGHT
var _movement: Vector2 = Vector2.ZERO
var _attack_age: float = -1.0
var _attack_consumed: bool = false
var _cooldown: float = 0.0
var _shadow: Polygon2D = null


func _ready() -> void:
	assert(profile != null and player != null and squad != null)
	process_physics_priority = 5
	health = profile.maximum_health
	brain = BRAINS[profile.kind].new() as RefCounted
	_cooldown = 0.15 + fmod(phase, 0.35)
	collision_layer = 4
	collision_mask = 5
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.02
	z_index = 2
	for group: StringName in [&"enemy_bodies", &"enemy_ai_actor", &"insects"]: add_to_group(group)
	add_to_group(StringName("insect_%s" % profile.kind))
	set_meta(&"enemy_ai_role", EnemyAIEnums.Role.MELEE)
	set_meta(&"enemy_ai_is_attacking", false)
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = profile.body_radius
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "BodyCollision"
	collision.shape = circle
	add_child(collision)
	_shadow = Polygon2D.new()
	_shadow.name = "Shadow"
	_shadow.color = Color(0.145, 0.075, 0.102, 0.40)
	_shadow.z_index = -1
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(12): points.append(Vector2.from_angle(index * TAU / 12.0) * Vector2(profile.body_radius, 2.0))
	_shadow.polygon = points
	add_child(_shadow)
	visual = VISUAL.new() as AnimatedSprite2D
	visual.name = "Sprite"
	visual.set("kind", profile.kind)
	visual.set("palette_variant", palette_variant)
	visual.set("floor_height", floor_height)
	visual.scale = Vector2.ONE * profile.visual_scale
	add_child(visual)
	visual.connect("death_finished", _finish_death)


func _physics_process(delta: float) -> void:
	if dying: return
	if is_in_group(&"immobilized_enemies"):
		velocity = Vector2.ZERO
		hit_velocity = Vector2.ZERO
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not engaged and global_position.distance_squared_to(home_position) < 9.0 and _movement.is_zero_approx() and hit_velocity.is_zero_approx():
		return
	if engaged and not suspended and is_instance_valid(player) and not player.dead and not player.intro_locked:
		brain.call("tick", self, delta)
		_update_attack(delta)
	else:
		cancel_attack()
		drive_to(home_position)
	hit_velocity = hit_velocity.move_toward(Vector2.ZERO, delta * 300.0)
	_move_toward_velocity(delta)
	velocity = _movement + hit_velocity
	_guard_floor_step(delta)
	move_and_slide()
	if height_query.is_valid(): floor_height = float(height_query.call(global_position))
	_shadow.position.y = -floor_height
	visual.set("floor_height", floor_height)
	visual.call("update_pose", velocity.length_squared() > 4.0, attack_in_progress(), _attack_age, profile, attack_direction if attack_in_progress() else _look)


func _move_toward_velocity(delta: float) -> void:
	if profile.kind == &"little" and engaged and not suspended and _movement.length_squared() > 1.0 and desired_velocity.length_squared() > 1.0:
		var heading: float = rotate_toward(_movement.angle(), desired_velocity.angle(), delta * 6.0)
		var direction: Vector2 = Vector2.from_angle(heading)
		var navigation: EnemyNavigationGrid = squad.get("navigation") as EnemyNavigationGrid
		if navigation != null and navigation.corridor_clear(global_position, global_position + direction * 12.0):
			# Turn around in an arc without cancelling opposing velocities into a stop.
			_movement = direction * move_toward(_movement.length(), desired_velocity.length(), profile.acceleration * delta)
			return
	_movement = _movement.move_toward(desired_velocity, profile.acceleration * delta)


func _guard_floor_step(delta: float) -> void:
	var ground: Callable = squad.get("floor_query") as Callable
	if not ground.is_valid() or bool(ground.call(global_position + velocity * delta)): return
	# Steering/knockback must not cut an uncollided river corner between grid samples.
	var horizontal: Vector2 = Vector2(velocity.x, 0)
	var vertical: Vector2 = Vector2(0, velocity.y)
	var slide: Vector2 = Vector2.ZERO
	if bool(ground.call(global_position + horizontal * delta)): slide = horizontal
	if bool(ground.call(global_position + vertical * delta)) and vertical.length_squared() > slide.length_squared(): slide = vertical
	velocity = slide
	_movement = slide
	hit_velocity = Vector2.ZERO


func player_distance() -> float:
	return global_position.distance_to(player.global_position)


func approach_player(speed_factor: float = 1.0) -> void:
	var away: Vector2 = player.global_position.direction_to(global_position)
	if away.is_zero_approx(): away = Vector2.from_angle(phase)
	drive_to(player.global_position + away * (profile.body_radius + 6.0), speed_factor)
	_look = global_position.direction_to(player.global_position)


func drive_to(goal: Vector2, speed_factor: float = 1.0, curve: float = 0.0) -> void:
	if not is_instance_valid(squad):
		stop_motion()
		return
	var direction: Vector2 = squad.call("steer", self, goal, curve) as Vector2
	desired_velocity = direction * profile.movement_speed * speed_factor
	if not direction.is_zero_approx(): _look = direction


func drive_direction(direction: Vector2, speed: float) -> void:
	desired_velocity = direction * speed


func stop_motion() -> void:
	desired_velocity = Vector2.ZERO


func can_start_attack() -> bool:
	return is_alive() and _cooldown <= 0.0 and not attack_in_progress() and player_distance() <= profile.attack_range and _line_clear()


func begin_attack() -> void:
	if not can_start_attack(): return
	attack_direction = global_position.direction_to(player.global_position)
	if attack_direction.is_zero_approx(): attack_direction = _look
	_attack_age = 0.0
	_attack_consumed = false
	attacks_started += 1
	set_meta(&"enemy_ai_is_attacking", true)


func attack_in_progress() -> bool:
	return _attack_age >= 0.0


func attack_is_active() -> bool:
	return _attack_age >= profile.windup and _attack_age < profile.windup + profile.active_duration


func _update_attack(delta: float) -> void:
	if not attack_in_progress(): return
	var previous_age: float = _attack_age
	_attack_age += delta
	# Crossing the whole active interval in one frame still resolves exactly once.
	if not _attack_consumed and previous_age < profile.windup + profile.active_duration and _attack_age >= profile.windup:
		_resolve_contact()
	if dying: return
	if _attack_age >= profile.attack_duration():
		cancel_attack()
		_cooldown = profile.attack_cooldown
		brain.call("on_attack_finished", self)


func _resolve_contact() -> void:
	if not is_instance_valid(player) or player.dead or player.intro_locked: return
	var offset_to_player: Vector2 = player.global_position - global_position
	if offset_to_player.length() > profile.attack_reach: return
	if offset_to_player.length() > 0.01 and offset_to_player.normalized().dot(attack_direction) < 0.20: return
	if not _line_clear() or absf(floor_height - player.floor_height) > 12.0: return
	_attack_consumed = true
	if player.is_dashing():
		attack_resolved.emit(self, false)
		return
	if player.try_parry_enemy_attack(self, player.global_position):
		attack_resolved.emit(self, false)
		return
	var before: float = player.health
	player.receive_contact_damage(profile.damage, attack_direction, 34.0 if profile.kind == &"tall" else 0.0, self)
	var connected: bool = player.health < before
	if connected: hits_landed += 1
	attack_resolved.emit(self, connected)


func _line_clear() -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, player.global_position, 1)
	query.exclude = [get_rid(), player.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func cancel_attack() -> void:
	_attack_age = -1.0
	set_meta(&"enemy_ai_is_attacking", false)


func owns_fly_turn() -> bool:
	return is_instance_valid(squad) and squad.get("fly_attacker") == self


func can_take_fly_turn() -> bool:
	return is_alive() and profile.kind == &"fly" and bool(brain.call("can_take_turn"))


func set_engaged(value: bool) -> void:
	if engaged == value: return
	engaged = value
	if not value:
		cancel_attack()
		brain.call("reset", self)
		stop_motion()


func get_combat_faction() -> StringName:
	return &"monsters"


func is_alive() -> bool:
	return not dying and health > 0.0


func get_current_health() -> float:
	return health


func get_separation_radius() -> float:
	return profile.body_radius


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": Vector2(0, -8.0 * profile.visual_scale - floor_height), "radius": 6.0 * profile.visual_scale, "height": 18.0 * profile.visual_scale}


func _finish_death() -> void:
	if is_instance_valid(remains_system):
		var last: int = visual.sprite_frames.get_frame_count(&"death") - 1
		var texture: Texture2D = visual.sprite_frames.get_frame_texture(&"death", last)
		remains_system.call("leave_sprite", texture, global_position,
			visual.offset + visual.position / visual.scale, visual.scale, visual.flip_h, profile.kind)
	queue_free()


func take_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0: return
	health = maxf(health - amount, 0.0)
	visual.call("flash_hit")
	damaged.emit(amount, health)
	if health <= 0.0:
		dying = true
		_stop_combat()
		_shadow.hide()
		visual.call("begin_death")
		died.emit(self)
	elif engaged:
		brain.call("on_damaged", self)


func receive_impact(direction: Vector2, impulse: float, _recovery: float = 0.055) -> void:
	if is_alive(): hit_velocity = (hit_velocity + direction.normalized() * impulse * profile.knockback_resistance).limit_length(16.0 if profile.kind == &"tall" else 65.0)


func dismiss() -> void:
	dying = true
	_stop_combat()
	queue_free()


func _stop_combat() -> void:
	cancel_attack()
	desired_velocity = Vector2.ZERO
	_movement = Vector2.ZERO
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	for group: StringName in [&"enemy_bodies", &"enemy_ai_actor", &"insects", StringName("insect_%s" % profile.kind)]: remove_from_group(group)
