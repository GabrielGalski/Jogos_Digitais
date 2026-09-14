extends Node2D
## Only the opening line enters from below; reinforcements are always offscreen.
signal horde_cleared
signal spawning_finished
signal opening_arrived
signal enemy_spawned(enemy: Minotaur)
const MINOTAUR: PackedScene = preload("res://scenes/enemies/minotaur.tscn")
@export var spawn_duration: float = 35.0
@export var spawn_interval: float = 0.45
@export var maximum_alive: int = 32
@export var opening_spacing: float = 29.0
@export var opening_entrance_speed: float = 100.0
@export var elite_spawn_interval: float = 0.75
@export var elite_maximum_alive: int = 12
var active: bool = false
var spawning: bool = false
var elite_phase: bool = false
var elapsed: float = 0.0
var spawn_left: float = 0.0
var opening_pending: bool = false
var opening_entering: bool = false
var opening_targets: Dictionary = {}
var alive: Array[Minotaur] = []
var total_spawned: int = 0
var total_killed: int = 0
var initial_count: int = 0
var last_spawn_was_opening: bool = false
var target: Player
var chamber: Node2D
var bounds: Rect2
var random: RandomNumberGenerator = RandomNumberGenerator.new()

func setup(player: Player, arena: Node2D) -> void:
	target = player
	chamber = arena
	bounds = Rect2(arena.to_global(player.arena_bounds.position), player.arena_bounds.size * arena.global_scale)
	random.randomize()

func start_horde() -> void:
	if active:
		return
	active = true
	spawning = false
	elite_phase = false
	opening_pending = true
	opening_entering = false
	opening_targets.clear()
	elapsed = 0.0
	spawn_left = spawn_interval

func start_elite_horde() -> void:
	if active:
		return
	active = true
	spawning = true
	elite_phase = true
	opening_pending = false
	opening_entering = false
	opening_targets.clear()
	spawn_left = 0.05

func visible_world_rect() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var screen: Vector2 = get_viewport_rect().size
	var corners: PackedVector2Array = PackedVector2Array([inverse * Vector2.ZERO, inverse * Vector2(screen.x, 0), inverse * screen, inverse * Vector2(0, screen.y)])
	var minimum: Vector2 = corners[0]
	var maximum: Vector2 = minimum
	for point: Vector2 in corners:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)

func _physics_process(delta: float) -> void:
	if not active:
		return
	if opening_pending:
		opening_pending = false
		_spawn_opening()
		return
	if opening_entering:
		_update_opening_entrance(delta)
		return
	if spawning:
		if elite_phase:
			spawn_left -= delta
			if spawn_left <= 0.0 and alive.size() < elite_maximum_alive:
				spawn_left = elite_spawn_interval
				_spawn_offscreen(true)
		else:
			elapsed += delta
			if elapsed >= spawn_duration:
				spawning = false
				spawning_finished.emit()
			else:
				spawn_left -= delta
				if spawn_left <= 0.0:
					spawn_left = spawn_interval
					if alive.size() < maximum_alive:
						_spawn_offscreen()
	if not spawning and alive.is_empty():
		active = false
		horde_cleared.emit()

func _spawn_opening() -> void:
	var opening_rect: Rect2 = visible_world_rect().intersection(bounds.grow(-16.0))
	if not opening_rect.has_area():
		return
	last_spawn_was_opening = true
	for row: int in range(2):
		var x: float = opening_rect.position.x + 14.0 + float(row) * opening_spacing * 0.5
		var destination_y: float = opening_rect.end.y - 14.0 - float(row) * 30.0
		var spawn_y: float = bounds.end.y - 28.0 - float(row) * 28.0
		while x < opening_rect.end.x - 14.0 and alive.size() < maximum_alive:
			var destination: Vector2 = Vector2(x, destination_y)
			var spawn_point: Vector2 = Vector2(x, spawn_y)
			if can_spawn_at(destination) and can_spawn_at(spawn_point):
				var enemy: Minotaur = _spawn(spawn_point)
				opening_targets[enemy.get_instance_id()] = destination
			x += opening_spacing
	initial_count = alive.size()
	last_spawn_was_opening = false
	if initial_count == 0:
		_begin_regular_spawning()
	else:
		opening_entering = true

func _update_opening_entrance(delta: float) -> void:
	var all_arrived: bool = true
	for enemy: Minotaur in alive:
		if not is_instance_valid(enemy) or not opening_targets.has(enemy.get_instance_id()):
			continue
		var destination: Vector2 = opening_targets.get(enemy.get_instance_id(), enemy.global_position)
		if enemy.global_position.distance_to(destination) > 0.5:
			all_arrived = false
			enemy.global_position = enemy.global_position.move_toward(destination, opening_entrance_speed * delta)
	if all_arrived:
		opening_entering = false
		opening_targets.clear()
		_begin_regular_spawning()

func _begin_regular_spawning() -> void:
	spawning = true
	elapsed = 0.0
	spawn_left = spawn_interval
	opening_arrived.emit()

func _spawn_offscreen(empowered: bool = false) -> void:
	var view: Rect2 = visible_world_rect().grow(28.0)
	var safe: Rect2 = bounds.grow(-22.0)
	# Sample every side of the visible region, then the remaining map if at an edge.
	for attempt: int in range(160):
		var candidate: Vector2
		if attempt < 80:
			match random.randi_range(0, 3):
				0: candidate = Vector2(view.position.x - random.randf_range(1.0, 44.0), random.randf_range(view.position.y, view.end.y))
				1: candidate = Vector2(view.end.x + random.randf_range(1.0, 44.0), random.randf_range(view.position.y, view.end.y))
				2: candidate = Vector2(random.randf_range(view.position.x, view.end.x), view.position.y - random.randf_range(1.0, 44.0))
				_: candidate = Vector2(random.randf_range(view.position.x, view.end.x), view.end.y + random.randf_range(1.0, 44.0))
		else:
			candidate = Vector2(random.randf_range(safe.position.x, safe.end.x), random.randf_range(safe.position.y, safe.end.y))
		if safe.has_point(candidate) and not view.has_point(candidate) and can_spawn_at(candidate):
			_spawn(candidate, empowered)
			return
	# No safe offscreen space: postpone this reinforcement, never spawn on Nox.

func can_spawn_at(point: Vector2) -> bool:
	if not bounds.grow(-16.0).has_point(point) or point.distance_to(target.global_position) < 86.0:
		return false
	for enemy: Minotaur in alive:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(point) < 27.0:
			return false
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 14.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 5
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _spawn(point: Vector2, empowered: bool = false) -> Minotaur:
	var enemy: Minotaur = MINOTAUR.instantiate() as Minotaur
	enemy.position = to_local(point)
	add_child(enemy)
	enemy.setup(target, chamber, bounds)
	enemy.set_empowered(empowered)
	enemy.reset_physics_interpolation()
	enemy.died.connect(_on_enemy_died)
	alive.append(enemy)
	total_spawned += 1
	enemy_spawned.emit(enemy)
	return enemy

func _on_enemy_died(enemy: Minotaur) -> void:
	if alive.has(enemy):
		alive.erase(enemy)
		opening_targets.erase(enemy.get_instance_id())
		total_killed += 1

