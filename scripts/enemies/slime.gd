extends CharacterBody2D
signal died(actor: Node2D)
signal damaged(amount: float, remaining_health: float)
enum State { APPROACH, WINDUP, AIRBORNE, LANDING, RECOVER, RETREAT }
const VISUAL: Script = preload("res://scripts/visual/slime_visual.gd")
const PALETTE: Script = preload("res://scripts/visual/biome_enemy_palette.gd")
var profile: SlimeProfile = null
var player: Player = null
var squad: Node2D = null
var jump_coordinator: Node = null
var remains_system: Node2D = null
var height_query: Callable = Callable()
var neighbors: Array[Node2D] = []
var home_position: Vector2 = Vector2.ZERO
var floor_height: float = 0.0
var phase: float = 0.0
var health: float = 0.0
var dying: bool = false
var engaged: bool = false
var state: State = State.APPROACH
var jumps_started: int = 0
var hits_landed: int = 0
var landings: int = 0
var desired_velocity: Vector2 = Vector2.ZERO
var hit_velocity: Vector2 = Vector2.ZERO
var jump_height: float = 0.0
var visual: AnimatedSprite2D = null
var _shadow: Polygon2D = null
var _movement: Vector2 = Vector2.ZERO
var _look: Vector2 = Vector2.RIGHT
var _age: float = 0.0
var _cooldown: float = 0.0
var _jump_goal: Vector2 = Vector2.ZERO
var _jump_start: Vector2 = Vector2.ZERO
var _retreat_goal: Vector2 = Vector2.ZERO
var _slam_consumed: bool = false
var _splash_age: float = 1.0
var _aim_left: float = 0.0
var _air_exclusions: Array[PhysicsBody2D] = []


func _ready() -> void:
	assert(profile != null and player != null and squad != null)
	health = profile.maximum_health
	_cooldown = 0.25 + fmod(phase, 0.55)
	process_physics_priority = 5
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.02
	collision_layer = 4
	collision_mask = 5
	z_index = 2
	for group: StringName in [&"enemy_bodies", &"enemy_ai_actor", &"slimes"]: add_to_group(group)
	set_meta(&"enemy_ai_role", EnemyAIEnums.Role.MELEE)
	set_meta(&"enemy_ai_is_attacking", false)
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = profile.body_radius
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.name = "BodyCollision"
	collider.shape = shape
	add_child(collider)
	_shadow = Polygon2D.new()
	_shadow.z_index = -1
	_shadow.color = Color(0.05, 0.12, 0.16, 0.35)
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(12): points.append(Vector2.from_angle(index * TAU / 12.0) * Vector2(7, 2))
	_shadow.polygon = points
	add_child(_shadow)
	visual = VISUAL.new() as AnimatedSprite2D
	visual.name = "Sprite"
	visual.set("floor_height", floor_height)
	add_child(visual)
	visual.connect("death_finished", _finish_death)


func _physics_process(delta: float) -> void:
	if dying: return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_splash_age += delta
	if not engaged and global_position.distance_squared_to(home_position) < 9.0 and _movement.is_zero_approx() and hit_velocity.is_zero_approx(): return
	_age += delta
	_clear_air_exclusions(false)
	if engaged and not player.dead and not player.intro_locked: _tick(delta)
	else:
		cancel_attack()
		drive_to(home_position)
	if dying: return
	hit_velocity = hit_velocity.move_toward(Vector2.ZERO, delta * 300.0)
	if state == State.AIRBORNE:
		var progress: float = clampf(_age / profile.flight_time, 0.0, 1.0)
		var planned: Vector2 = _jump_start.lerp(_jump_goal, progress)
		var step: Vector2 = (planned - global_position).limit_length(profile.maximum_jump / profile.flight_time * 1.2 * delta)
		velocity = step / maxf(delta, 0.00001)
		jump_height = sin(progress * PI) * profile.jump_height
	else:
		_movement = _movement.move_toward(desired_velocity, profile.acceleration * delta)
		velocity = _movement + hit_velocity
	_guard_floor_step(delta)
	move_and_slide()
	if height_query.is_valid(): floor_height = float(height_query.call(global_position))
	if state == State.AIRBORNE and _age >= profile.flight_time: _land()
	if dying: return
	_shadow.position.y = -floor_height
	_shadow.scale = Vector2.ONE * (1.0 - jump_height / 80.0)
	visual.set("floor_height", floor_height)
	visual.set("jump_height", jump_height)
	visual.call("update_pose", attack_frame(), _look, velocity.length())
	if _splash_age < 0.25 + delta: queue_redraw()


func _tick(delta: float) -> void:
	match state:
		State.APPROACH:
			var away: Vector2 = player.global_position.direction_to(global_position)
			if away.is_zero_approx(): away = Vector2.from_angle(phase)
			var waiting: Vector2 = player.global_position + away.rotated(0.16) * (64.0 + fmod(phase, 3.0) * 4.0)
			drive_to(waiting if global_position.distance_to(player.global_position) <= profile.attack_range + 12.0 else player.global_position)
			if _cooldown <= 0.0 and global_position.distance_to(player.global_position) <= profile.attack_range:
				begin_attack()
		State.WINDUP:
			desired_velocity = Vector2.ZERO
			_aim_left -= delta
			if _aim_left <= 0.0:
				_aim_left = 0.07
				_jump_goal = jump_coordinator.call("refresh", self, _predicted_landing()) as Vector2
			if _age >= profile.windup and bool(jump_coordinator.call("can_takeoff", self)):
				if _landing_valid(_jump_goal):
					jump_coordinator.call("takeoff", self)
					state = State.AIRBORNE
					_age = 0.0
					_jump_start = global_position
					_movement = Vector2.ZERO
					hit_velocity = Vector2.ZERO
					collision_mask = 1 # Other monsters cannot block an airborne leap.
					_begin_air_exclusions()
				else: _begin_retreat()
		State.LANDING:
			desired_velocity = Vector2.ZERO
			if _age >= profile.landing_time:
				state = State.RECOVER
				_age = 0.0
		State.RECOVER:
			desired_velocity = Vector2.ZERO
			if _age >= profile.recovery: _begin_retreat()
		State.RETREAT:
			drive_to(_retreat_goal, profile.retreat_speed)
			if _age >= profile.retreat_time or global_position.distance_to(_retreat_goal) < 8.0:
				state = State.APPROACH
				_age = 0.0


func can_queue_jump() -> bool:
	return is_alive() and engaged and state == State.APPROACH and _cooldown <= 0.0 and is_instance_valid(player) and not player.dead and not player.intro_locked and global_position.distance_to(player.global_position) <= profile.attack_range


func begin_attack() -> void:
	if not can_queue_jump(): return
	var reservation: Dictionary = jump_coordinator.call("request", self, _predicted_landing()) as Dictionary
	if reservation.is_empty(): return
	_jump_goal = reservation.goal as Vector2
	state = State.WINDUP
	_age = 0.0
	_slam_consumed = false
	_aim_left = 0.07
	desired_velocity = Vector2.ZERO
	_look = global_position.direction_to(_jump_goal)
	jumps_started += 1
	set_meta(&"enemy_ai_is_attacking", true)


func _predicted_landing() -> Vector2:
	var predicted: Vector2 = player.global_position + (player.velocity * 0.10).limit_length(12.0)
	return global_position + (predicted - global_position).limit_length(profile.maximum_jump)


func _landing_valid(point: Vector2) -> bool:
	if global_position.distance_to(point) > profile.maximum_jump: return false
	var ground: Callable = squad.get("floor_query") as Callable
	if not ground.is_valid() or not bool(ground.call(point)): return false
	if height_query.is_valid() and absf(float(height_query.call(point)) - floor_height) > 12.0: return false
	if not _line_clear(point): return false
	squad.call("_ensure_navigation")
	return (squad.get("navigation") as EnemyNavigationGrid).corridor_clear(global_position, point)


func _line_clear(point: Vector2) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, point, 1)
	query.exclude = [get_rid(), player.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _land() -> void:
	jump_height = 0.0
	# Flight velocity must never become ground movement after an edge correction.
	velocity = Vector2.ZERO
	_movement = Vector2.ZERO
	desired_velocity = Vector2.ZERO
	hit_velocity = Vector2.ZERO
	jump_coordinator.call("landed", self)
	collision_mask = 5
	state = State.LANDING
	_age = 0.0
	_splash_age = 0.0
	_jump_goal = global_position
	landings += 1
	_cooldown = profile.attack_cooldown
	resolve_slam()
	queue_redraw()


func resolve_slam() -> void:
	if _slam_consumed or dying: return
	_slam_consumed = true
	if player.dead or player.intro_locked or player.is_dashing(): return
	if global_position.distance_to(player.global_position) > profile.blast_radius: return
	if absf(floor_height - player.floor_height) > 12.0 or not _line_clear(player.global_position): return
	if player.try_parry_enemy_attack(self, player.global_position): return
	var before: float = player.health
	player.receive_contact_damage(profile.damage, global_position.direction_to(player.global_position), 18.0)
	if player.health < before: hits_landed += 1


func _begin_retreat() -> void:
	cancel_attack()
	state = State.RETREAT
	_age = 0.0
	var away: Vector2 = player.global_position.direction_to(global_position)
	if away.is_zero_approx(): away = -_look
	_retreat_goal = home_position
	var ground: Callable = squad.get("floor_query") as Callable
	for angle: float in [0.0, 0.50, -0.50, 1.0, -1.0]:
		var goal: Vector2 = global_position + away.rotated(angle) * profile.retreat_distance
		var anchor: Vector2 = squad.get("anchor") as Vector2
		if goal.distance_to(anchor) < float(squad.get("anchor_leash")) - 12.0 and (not ground.is_valid() or bool(ground.call(goal))):
			_retreat_goal = goal
			break


func drive_to(goal: Vector2, speed: float = -1.0) -> void:
	var direction: Vector2 = squad.call("steer", self, goal) as Vector2
	desired_velocity = direction * (profile.movement_speed if speed < 0.0 else speed)
	if not direction.is_zero_approx(): _look = direction


func _guard_floor_step(delta: float) -> void:
	var ground: Callable = squad.get("floor_query") as Callable
	if not ground.is_valid() or bool(ground.call(global_position + velocity * delta)): return
	var horizontal: Vector2 = Vector2(velocity.x, 0)
	var vertical: Vector2 = Vector2(0, velocity.y)
	velocity = Vector2.ZERO
	if bool(ground.call(global_position + horizontal * delta)): velocity = horizontal
	if bool(ground.call(global_position + vertical * delta)) and vertical.length_squared() > velocity.length_squared(): velocity = vertical
	_movement = Vector2.ZERO if state == State.AIRBORNE else velocity
	hit_velocity = Vector2.ZERO


func attack_frame() -> int:
	match state:
		State.WINDUP: return mini(4, floori(_age / profile.windup * 5.0))
		State.AIRBORNE: return 5 + mini(2, floori(_age / profile.flight_time * 3.0))
		State.LANDING: return 8 + mini(1, floori(_age / profile.landing_time * 2.0))
		State.RECOVER: return 10 + mini(1, floori(_age / profile.recovery * 2.0))
	return -1


func cancel_attack() -> void:
	if is_instance_valid(jump_coordinator): jump_coordinator.call("release", self)
	state = State.APPROACH
	jump_height = 0.0
	velocity = Vector2.ZERO
	_movement = Vector2.ZERO
	desired_velocity = Vector2.ZERO
	hit_velocity = Vector2.ZERO
	collision_mask = 5
	_splash_age = 1.0
	set_meta(&"enemy_ai_is_attacking", false)
	queue_redraw()


func set_engaged(value: bool) -> void:
	engaged = value
	if not value:
		cancel_attack()
		_cooldown = maxf(_cooldown, 0.35)


func is_alive() -> bool:
	return not dying and health > 0.0


func get_current_health() -> float:
	return health


func get_combat_faction() -> StringName:
	return &"monsters"


func get_separation_radius() -> float:
	return profile.body_radius


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": Vector2(0, -8.0 - floor_height - jump_height), "radius": 7.0, "height": 16.0}


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
	elif engaged and state != State.AIRBORNE: _begin_retreat()


func receive_impact(direction: Vector2, impulse: float, _recovery: float = 0.055) -> void:
	if is_alive() and state != State.AIRBORNE: hit_velocity = (hit_velocity + direction.normalized() * impulse * 0.40).limit_length(55.0)


func _begin_air_exclusions() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var body: PhysicsBody2D = node as PhysicsBody2D
		if body == null or body == self or _air_exclusions.has(body): continue
		add_collision_exception_with(body)
		_air_exclusions.append(body)
	if not _air_exclusions.has(player):
		add_collision_exception_with(player)
		_air_exclusions.append(player)


func _clear_air_exclusions(force: bool) -> void:
	if state == State.AIRBORNE and not force: return
	for index: int in range(_air_exclusions.size() - 1, -1, -1):
		var body: PhysicsBody2D = _air_exclusions[index]
		if not is_instance_valid(body):
			_air_exclusions.remove_at(index)
			continue
		var radius: float = float(body.call("get_separation_radius")) if body.has_method("get_separation_radius") else 8.0
		if force or global_position.distance_to(body.global_position) >= profile.body_radius + radius + 2.0:
			remove_collision_exception_with(body)
			_air_exclusions.remove_at(index)


func _finish_death() -> void:
	if is_instance_valid(remains_system):
		var texture: Texture2D = visual.sprite_frames.get_frame_texture(&"death", 5)
		remains_system.call("leave_sprite", texture, global_position, visual.offset + visual.position,
			Vector2.ONE, visual.flip_h, &"slime", PALETTE.remains_texture)
	queue_free()


func _stop_combat() -> void:
	cancel_attack()
	desired_velocity = Vector2.ZERO
	_movement = Vector2.ZERO
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	_clear_air_exclusions(true)
	for group: StringName in [&"enemy_bodies", &"enemy_ai_actor", &"slimes"]: remove_from_group(group)


func dismiss() -> void:
	dying = true
	_stop_combat()
	queue_free()


func _draw() -> void:
	if dying: return
	if _splash_age < 0.25:
		var progress: float = _splash_age / 0.25
		draw_arc(Vector2(0, -floor_height), profile.blast_radius * (0.65 + progress * 0.35), 0.0, TAU, 32, Color(0.60, 0.89, 0.85, 0.70 * (1.0 - progress)), 1.0)
