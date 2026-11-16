extends "res://scripts/enemies/spirit_ghost.gd"

const CATALOG: Script = preload("res://scripts/enemies/open_world_horde_catalog.gd")
const SHOT: Script = preload("res://scripts/combat/projectiles/open_world_horde_shot.gd")
const SPARK: Texture2D = preload("res://assets/enemies/open_world_horde/lizard_monk/effects/sprSparkle.png")
var species: String
var stats: Dictionary
var variant: Array
var target: Player
var heights: Callable
var cooldown: float
var sight_timer: float = 0.0
var sight_clear: bool = false
var windup: float = 0.0
var burst_delay: float = 0.0
var aim: Vector2
var spark: Sprite2D
var hit_time: float = 0.0


func configure(kind: String, subject: Player, height_query: Callable) -> void:
	species = kind
	stats = CATALOG.TYPES[kind]
	var bodies: Array = stats.bodies
	variant = bodies.pick_random() as Array
	target = subject
	heights = height_query
	cooldown = randf_range(0.0, float(stats.interval))


func _ready() -> void:
	super()
	collision_mask = 5
	hit_pose_hold = 0.12
	remove_from_group(&"spirit_ghosts")
	add_to_group(&"open_world_horde_enemies")
	_sprite.texture = variant[0] as Texture2D
	_sprite.hframes = 4
	if species == "lizard_monk":
		spark = Sprite2D.new()
		spark.texture = SPARK
		spark.hframes = 4
		spark.position.y = -10.0
		spark.hide()
		_sprite.add_child(spark)


func _process(delta: float) -> void:
	_age += delta
	hit_time = maxf(0.0, hit_time - delta)
	var t: float = 1.0 - hit_time / 0.20
	var bounce: float = sin(PI * t)
	var squash: float = (1.0 - t) * cos(TAU * t)
	_sprite.scale = Vector2(1.0 + 0.28 * squash, 1.0 - 0.24 * squash)
	_sprite.offset = Vector2(0.0, -5.0 * bounce)
	if hit_time <= 0.0 and windup > 0.0:
		_sprite.offset.x = -2.0 * signf(aim.x)
		_sprite.scale = Vector2(1.08, 0.92)
	(_sprite.material as ShaderMaterial).set_shader_parameter(&"flash_amount", clampf((hit_time - 0.105) / 0.035, 0.0, 1.0))
	_sprite.frame = int((_age + phase) * 9.0) % 4
	if is_instance_valid(target):
		_sprite.flip_h = target.global_position.x < global_position.x
	if spark != null:
		spark.visible = windup > 0.0 and not dying
		spark.frame = int(_age * 20.0) % 4


func take_damage(amount: float) -> void:
	if is_alive() and amount > 0.0:
		hit_time = 0.20
		(_sprite.material as ShaderMaterial).set_shader_parameter(&"flash_amount", 1.0)
	super(amount)


func get_visual_center_of_mass() -> Vector2:
	return _sprite.to_global(_sprite.offset)


func _emit_remains() -> void:
	remains_system.call("emit_spirit", get_visual_center_of_mass(), global_position,
		last_hit_direction, velocity + hit_velocity, variant[1], variant[2])


func combat_direction(forward: Vector2, distance: float, delta: float) -> Vector2:
	var reach: float = float(stats.reach)
	var melee: bool = reach < 50.0
	sight_timer -= delta
	if distance <= reach:
		cooldown = maxf(0.0, cooldown - delta)
		if sight_timer <= 0.0:
			sight_clear = _clear_shot()
			sight_timer = 0.12
	if burst_delay > 0.0:
		burst_delay -= delta
		if burst_delay <= 0.0 and distance <= reach and _clear_shot():
			_fire()
	elif windup > 0.0:
		windup -= delta
		if windup <= 0.0 and distance <= reach and _clear_shot():
			_fire()
			if species == "lizard_monk":
				burst_delay = 0.18
	elif cooldown <= 0.0 and distance <= reach and sight_clear:
		aim = global_position.direction_to(target.global_position)
		windup = 0.15 if melee else 0.25
		cooldown = float(stats.interval)
	if distance > reach or not sight_clear or (windup <= 0.0 and not melee and distance > reach * 0.8):
		return forward
	if melee:
		return forward * clampf((distance - 13.0) / 16.0, 0.0, 1.0)
	var lateral: Vector2 = global_position.direction_to(target.global_position).orthogonal()
	return lateral * sin(_age * 1.8 + phase) * 0.65 - forward * (0.4 if distance < reach * 0.45 else 0.0)


func _clear_shot() -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1)
	query.exclude = [target.get_rid(), get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _fire() -> void:
	var shot: SHOT = SHOT.new()
	shot.target = target
	shot.shooter = self
	shot.direction = aim
	shot.sheet = stats.shot
	shot.frames = stats.frames
	shot.speed = stats.speed
	shot.remaining = float(stats.travel) / float(stats.speed)
	shot.damage = contact_damage
	shot.height_query = heights
	shot._visual_height = float(heights.call(global_position)) if heights.is_valid() else 0.0
	shot.fire_impact = species == "batilisk"
	shot.position = position
	get_parent().add_child(shot)
