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
static var _body_bounds: Dictionary[Texture2D, Rect2] = {}
var floor_height: float = 0.0
var _hurt_center: Vector2 = Vector2.ZERO
var _hurt_radius: float = 6.0
var _hurt_height: float = 18.0


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
	# Ground collisions remain physical. Crowd spacing is handled by steering.
	collision_mask = 1
	hit_pose_hold = 0.12
	remove_from_group(&"spirit_ghosts")
	add_to_group(&"open_world_horde_enemies")
	_sprite.texture = variant[0] as Texture2D
	_sprite.hframes = 4
	var texture: Texture2D = _sprite.texture
	if not _body_bounds.has(texture):
		var source: Image = texture.get_image()
		if source.is_compressed():
			source.decompress()
		var frame_width: int = int(float(source.get_width()) / 4.0)
		var accumulated_bounds: Rect2 = Rect2()
		for index: int in range(4):
			var frame: Image = source.get_region(Rect2i(index * frame_width, 0, frame_width, source.get_height()))
			var frame_bounds: Rect2 = Rect2(frame.get_used_rect())
			accumulated_bounds = frame_bounds if accumulated_bounds.size.is_zero_approx() else accumulated_bounds.merge(frame_bounds)
		_body_bounds[texture] = accumulated_bounds
	var bounds: Rect2 = _body_bounds[texture]
	_hurt_center = bounds.get_center() - Vector2(texture.get_width() / 4.0, texture.get_height()) * 0.5
	_hurt_radius = clampf(bounds.size.x * 0.45, 6.0, 12.0)
	_hurt_height = maxf(bounds.size.y, _hurt_radius * 2.0)
	sync_floor_height()
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


func sync_floor_height() -> void:
	floor_height = float(heights.call(global_position)) if heights.is_valid() else 0.0
	_sprite.position = Vector2(0.0, -7.0 - roundf(floor_height))


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": _sprite.position + _hurt_center, "radius": _hurt_radius, "height": _hurt_height}


func get_separation_radius() -> float:
	return 17.0 if species == "bogslium" else 12.0


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
	var preferred_distance: float = reach * (0.64 + 0.16 * (0.5 + 0.5 * sin(phase)))
	if distance > reach or not sight_clear or (windup <= 0.0 and not melee and distance > preferred_distance):
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
	if get_parent().has_method("spawn_horde_projectile"):
		get_parent().call("spawn_horde_projectile", shot)
	else:
		get_parent().add_child(shot)
