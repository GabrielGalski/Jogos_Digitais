extends Node2D
## Scene-owned debris: ballistic flight, sleeping chunks, foot kicks and timed fade-out.
const PROFILE: Script = preload("res://scripts/visual/enemy_remains_profile.gd")
const PIECE: Script = preload("res://scripts/visual/enemy_remains_piece.gd")
const LAYER: Script = preload("res://scripts/visual/enemy_remains_layer.gd")
const CHUNK_SIZE: float = 128.0
const SHAPES: Array[Array] = [
	[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)],
	[Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)],
	[Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(2, 1)],
]
var spirit_profile: Resource = PROFILE.new()
var player: Player = null
var floor_query: Callable = Callable()
var active: Array[RefCounted] = []
var _chunks: Dictionary[Vector2i, Node2D] = {}
var _air: Node2D = null
var _textures: Array[Texture2D] = []
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _next_expiry: float = INF
var _previous_feet: Vector2 = Vector2.ZERO
var _sampled_player: bool = false


func _ready() -> void:
	process_physics_priority = 20
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_random.randomize()
	_textures = _make_textures(spirit_profile)
	_air = LAYER.new() as Node2D
	_air.name = "AirborneRemains"
	_air.z_index = 2
	_air.set("airborne", true)
	_air.set("pieces", active)
	_air.set("textures", _textures)
	add_child(_air)


func configure(query: Callable, subject: Player = null) -> void:
	floor_query = query
	player = subject
	_sampled_player = false


func emit_spirit(world_center: Vector2, world_ground: Vector2, impact: Vector2,
		inherited_velocity: Vector2 = Vector2.ZERO) -> void:
	var ground: Vector2 = to_local(world_ground)
	var center: Vector2 = to_local(world_center)
	var initial_ground: Vector2 = Vector2(center.x, ground.y)
	var amount: int = _random.randi_range(int(spirit_profile.get("minimum_pieces")), int(spirit_profile.get("maximum_pieces")))
	var bias: Vector2 = global_transform.basis_xform_inv(impact).normalized()
	var inherited: Vector2 = global_transform.basis_xform_inv(inherited_velocity).limit_length(130.0) * 0.12
	for index: int in range(amount):
		var piece: RefCounted = PIECE.new()
		piece.set("ground", initial_ground)
		piece.set("previous_ground", initial_ground)
		piece.set("height", maxf(ground.y - center.y, 0.0))
		piece.set("previous_height", piece.get("height"))
		var radial: Vector2 = Vector2.from_angle(TAU * float(index) / float(amount) + _random.randf_range(-0.35, 0.35))
		var direction: Vector2 = (radial + bias * 0.40).normalized()
		var speed: float = _random.randf_range(float(spirit_profile.get("minimum_speed")), float(spirit_profile.get("maximum_speed")))
		piece.set("velocity", direction * speed + inherited)
		piece.set("lift_velocity", _random.randf_range(float(spirit_profile.get("minimum_lift")), float(spirit_profile.get("maximum_lift"))))
		piece.set("angular_velocity", _random.randf_range(-7.0, 7.0))
		piece.set("texture_index", _random.randi_range(0, _textures.size() - 1))
		piece.set("profile", spirit_profile)
		piece.set("kick_after", _elapsed + 0.30)
		var expiry: float = _elapsed + float(spirit_profile.get("lifetime"))
		piece.set("expires_at", expiry)
		piece.set("fade_end_at", expiry + maxf(float(spirit_profile.get("fade_duration")), 0.001))
		active.append(piece)
	_air.queue_redraw()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_expire_settled()
	var had_active: bool = not active.is_empty()
	_interact_with_player(delta)
	for index: int in range(active.size() - 1, -1, -1):
		var piece: RefCounted = active[index]
		if _update_lifetime(piece):
			active.remove_at(index)
			continue
		piece.set("previous_ground", piece.get("ground"))
		piece.set("previous_height", piece.get("height"))
		if _simulate(piece, delta):
			active.remove_at(index)
	if had_active or not active.is_empty():
		_air.queue_redraw()


func _process(_delta: float) -> void:
	if not active.is_empty():
		_air.queue_redraw()


func _has_floor(point: Vector2) -> bool:
	return floor_query.is_valid() and bool(floor_query.call(to_global(point)))


func _update_lifetime(piece: RefCounted) -> bool:
	var expiry: float = float(piece.get("expires_at"))
	if _elapsed < expiry:
		return false
	var end: float = float(piece.get("fade_end_at"))
	piece.set("opacity", 1.0 - clampf((_elapsed - expiry) / maxf(end - expiry, 0.001), 0.0, 1.0))
	return _elapsed >= end


func _expire_settled() -> void:
	# Resting chunks remain cached until their earliest fragment starts fading.
	if _elapsed < _next_expiry:
		return
	_next_expiry = INF
	for key: Vector2i in _chunks.keys():
		var chunk: Node2D = _chunks[key]
		if _elapsed >= float(chunk.get("next_expiry")):
			var pieces: Array = chunk.get("pieces") as Array
			var next: float = INF
			for index: int in range(pieces.size() - 1, -1, -1):
				var piece: RefCounted = pieces[index] as RefCounted
				if _update_lifetime(piece):
					pieces.remove_at(index)
				else:
					next = minf(next, float(piece.get("expires_at")))
			if pieces.is_empty():
				_chunks.erase(key)
				chunk.queue_free()
				continue
			chunk.set("next_expiry", next)
			chunk.queue_redraw()
		_next_expiry = minf(_next_expiry, float(chunk.get("next_expiry")))


func _simulate(piece: RefCounted, delta: float) -> bool:
	var profile: Resource = piece.get("profile") as Resource
	var height: float = float(piece.get("height"))
	var ground: Vector2 = piece.get("ground") as Vector2
	var velocity: Vector2 = piece.get("velocity") as Vector2
	if bool(piece.get("falling")):
		var elapsed: float = float(piece.get("fall_elapsed")) + delta
		piece.set("fall_elapsed", elapsed)
		piece.set("ground", ground + velocity * delta)
		piece.set("height", height - (35.0 + elapsed * 120.0) * delta)
		return elapsed >= float(profile.get("void_fall_duration"))
	ground += velocity * delta
	var lift: float = float(piece.get("lift_velocity")) - float(profile.get("gravity")) * delta
	height += lift * delta
	piece.set("angle", float(piece.get("angle")) + float(piece.get("angular_velocity")) * delta)
	if height <= 0.0:
		height = 0.0
		if not _has_floor(ground):
			piece.set("falling", true)
		elif lift < -18.0 and int(piece.get("bounces")) < 2:
			lift = -lift * float(profile.get("restitution"))
			piece.set("bounces", int(piece.get("bounces")) + 1)
			velocity *= 0.62
			piece.set("angular_velocity", float(piece.get("angular_velocity")) * 0.5)
		else:
			lift = 0.0
			velocity = velocity.move_toward(Vector2.ZERO, float(profile.get("ground_drag")) * delta)
	else:
		velocity *= exp(-float(profile.get("air_drag")) * delta)
	piece.set("ground", ground)
	piece.set("velocity", velocity)
	piece.set("height", height)
	piece.set("lift_velocity", lift)
	if height <= 0.0 and lift == 0.0 and velocity.length_squared() < 4.0 and not bool(piece.get("falling")):
		return _sleep(piece)
	return false


func _chunk(point: Vector2) -> Vector2i:
	return Vector2i((point / CHUNK_SIZE).floor())


func _sleep(piece: RefCounted) -> bool:
	var ground: Vector2 = (piece.get("ground") as Vector2).round()
	# Rounding must not place a settled pixel over the edge of a gap.
	if not _has_floor(ground):
		piece.set("ground", ground)
		piece.set("falling", true)
		return false
	piece.set("ground", ground)
	piece.set("previous_ground", ground)
	piece.set("height", 0.0)
	piece.set("previous_height", 0.0)
	piece.set("velocity", Vector2.ZERO)
	piece.set("sleeping", true)
	var key: Vector2i = _chunk(ground)
	if not _chunks.has(key):
		var chunk: Node2D = LAYER.new() as Node2D
		chunk.name = "FloorRemains_%d_%d" % [key.x, key.y]
		chunk.position = Vector2(key) * CHUNK_SIZE
		chunk.z_index = -12
		chunk.set("draw_origin", chunk.position)
		chunk.set("textures", _textures)
		add_child(chunk)
		_chunks[key] = chunk
	var layer: Node2D = _chunks[key]
	(layer.get("pieces") as Array).append(piece)
	var expiry: float = float(piece.get("expires_at"))
	layer.set("next_expiry", minf(float(layer.get("next_expiry")), expiry))
	_next_expiry = minf(_next_expiry, expiry)
	layer.queue_redraw()
	return true


func _wake(piece: RefCounted, chunk: Node2D) -> void:
	var pieces: Array = chunk.get("pieces") as Array
	pieces.erase(piece)
	if pieces.is_empty():
		_chunks.erase(_chunk(piece.get("ground") as Vector2))
		chunk.queue_free()
	else:
		chunk.queue_redraw()
	piece.set("sleeping", false)
	piece.set("previous_ground", piece.get("ground"))
	piece.set("previous_height", 0.0)
	active.append(piece)


func _interact_with_player(delta: float) -> void:
	if not is_instance_valid(player):
		_sampled_player = false
		return
	var feet: Vector2 = to_local(player.to_global(Vector2(0, 7)))
	if not _sampled_player or player.dead or player.intro_locked:
		_previous_feet = feet
		_sampled_player = true
		return
	var motion: Vector2 = feet - _previous_feet
	var travel: float = motion.length()
	if travel > 32.0 or travel < delta * 6.0:
		_previous_feet = feet
		return
	var direction: Vector2 = motion / travel
	var speed: float = travel / maxf(delta, 0.0001)
	var radius: float = float(spirit_profile.get("kick_radius"))
	var region: Rect2 = Rect2(_previous_feet, Vector2.ZERO).expand(feet).grow(radius)
	for y: int in range(_chunk(region.position).y, _chunk(region.end).y + 1):
		for x: int in range(_chunk(region.position).x, _chunk(region.end).x + 1):
			var chunk: Node2D = _chunks.get(Vector2i(x, y)) as Node2D
			if chunk == null:
				continue
			for piece: RefCounted in (chunk.get("pieces") as Array).duplicate():
				if _kick_if_near(piece, feet, direction, speed):
					_wake(piece, chunk)
	for piece: RefCounted in active:
		if float(piece.get("height")) <= 2.0 and not bool(piece.get("falling")):
			_kick_if_near(piece, feet, direction, speed)
	_previous_feet = feet


func _kick_if_near(piece: RefCounted, feet: Vector2, direction: Vector2, speed: float) -> bool:
	if _elapsed < float(piece.get("kick_after")):
		return false
	var ground: Vector2 = piece.get("ground") as Vector2
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(ground, _previous_feet, feet)
	var profile: Resource = piece.get("profile") as Resource
	if ground.distance_squared_to(closest) > pow(float(profile.get("kick_radius")), 2.0):
		return false
	var away: Vector2 = (ground - feet).normalized()
	piece.set("velocity", direction * clampf(speed * 0.30, 12.0, 62.0) + away * 8.0)
	piece.set("height", maxf(float(piece.get("height")), 0.5))
	piece.set("lift_velocity", clampf(speed * 0.13, 14.0, 30.0))
	piece.set("angular_velocity", _random.randf_range(-5.0, 5.0))
	piece.set("bounces", 0)
	piece.set("kick_after", _elapsed + float(profile.get("kick_cooldown")))
	return true


func settled_count() -> int:
	var total: int = 0
	for chunk: Node2D in _chunks.values():
		total += (chunk.get("pieces") as Array).size()
	return total


func total_count() -> int:
	return active.size() + settled_count()


static func _make_textures(profile: Resource) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for pixels: Array in SHAPES:
		var image: Image = Image.create(5, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for pixel: Vector2 in pixels:
			for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var point: Vector2i = Vector2i(pixel) + Vector2i.ONE + offset
				image.set_pixelv(point, profile.get("outline_color") as Color)
		for pixel: Vector2 in pixels:
			image.set_pixelv(Vector2i(pixel) + Vector2i.ONE, profile.get("fill_color") as Color)
		textures.append(ImageTexture.create_from_image(image))
	return textures
