extends Node2D
## Room-local encounter state and physics. There is deliberately no encounter UI.
signal started
signal cleared
signal stage_changed(stage: int)
signal progress_changed(defeated: int, target: int)
signal aborted

const GHOST: Script = preload("res://scripts/enemies/spirit_ghost.gd")
const PROFILE: Script = preload("res://scripts/enemies/spirit_horde_profile.gd")
const NAVIGATION: Script = preload("res://scripts/enemies/spirit_horde_navigation.gd")
const BUCKET: float = 24.0
const SPACING: float = 16.0
const ARENA_BOUNDARY: Script = preload("res://scripts/dungeon/pedestal_arena_boundary.gd")
enum Phase { WAITING, ACTIVE, CLEARED, ABORTED }

var profile: Resource = PROFILE.new()
var trigger_bounds: Rect2 = Rect2()
var kill_target: int = 40
var clear_condition: String = "spirit_horde_1_clear"
var entry_condition: String = "spirit_horde_1_entry_open"
var player: Player = null
var gameplay: Node2D = null
var floor_query: Callable = Callable()
var remains_system: Node2D = null
var encounter_id: String = "spirit_horde_1"
var activate_on_enter: bool = true
var arena_radius: float = 0.0
var arena_center: Vector2 = Vector2.ZERO
var arena_region: Dictionary = {}
var arena_boundary: StaticBody2D = null
var _height_query: Callable = Callable()
var phase: Phase = Phase.WAITING
var defeated_count: int = 0
var difficulty_stage: int = 0
var actors: Array[Node2D] = []
var navigation: RefCounted = NAVIGATION.new()
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawn_remaining: float = 0.0
var _routing_remaining: float = 0.0
var _elapsed: float = 0.0
var _spawn_sequence: int = 0
var _buckets: Dictionary = {}
var _waypoints: Dictionary = {}
var _route_deadlines: Dictionary = {}
var _previous_player: Vector2 = Vector2.ZERO


func configure(config: Dictionary, area: Rect2, subject: Player, rules: Node2D, query: Callable, remains: Node2D = null, height_query: Callable = Callable()) -> void:
	trigger_bounds = area
	player = subject
	gameplay = rules
	floor_query = query
	remains_system = remains
	encounter_id = str(config.get("EncounterId", "spirit_horde_1"))
	activate_on_enter = bool(config.get("ActivateOnEnter", true))
	arena_radius = maxf(float(config.get("ArenaRadius", 0.0)), 0.0)
	arena_center = config.get("ArenaCenter", trigger_bounds.get_center()) as Vector2
	_height_query = height_query
	kill_target = maxi(int(config.get("KillTarget", 40)), 1)
	clear_condition = str(config.get("ClearCondition", clear_condition))
	entry_condition = str(config.get("EntryCondition", entry_condition))
	_random.randomize()
	if arena_radius <= 0.0:
		navigation.call("configure", trigger_bounds.grow(1024.0))
	_previous_player = to_local(player.global_position)
	gameplay.call("set_condition", clear_condition, false)
	gameplay.call("set_condition", entry_condition, true)
	player.defeated.connect(_on_player_defeated)
	if arena_radius > 0.0:
		arena_boundary = ARENA_BOUNDARY.new() as StaticBody2D
		arena_boundary.name = "ArenaBoundary"
		add_child(arena_boundary)
		arena_boundary.call("configure", arena_center, arena_radius, player, _height_query, config.get("AllowedArenaCells", {}) as Dictionary)
		arena_region = arena_boundary.get("region") as Dictionary


func can_begin() -> bool:
	if phase != Phase.WAITING:
		return false
	if arena_radius <= 0.0:
		return true
	var current: Node = gameplay.get_meta(&"active_pedestal_encounter") as Node if gameplay.has_meta(&"active_pedestal_encounter") else null
	return not player.dead and not player.intro_locked and not is_instance_valid(current) \
		and arena_boundary != null and bool(arena_boundary.call("has_point", to_local(player.global_position), 9.0))


func begin() -> void:
	if not can_begin():
		return
	phase = Phase.ACTIVE
	if arena_boundary != null:
		navigation.call("configure", trigger_bounds.grow(1024.0))
		gameplay.set_meta(&"active_pedestal_encounter", self)
		arena_boundary.call("set_active", true)
	gameplay.call("set_condition", entry_condition, false)
	started.emit()
	for index: int in range(int(profile.get("initial_pack"))):
		_spawn_one()
	_spawn_remaining = float(profile.get("spawn_interval"))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var subject: Vector2 = to_local(player.global_position)
	if player.intro_locked or player.dead:
		_previous_player = subject
		return
	if phase == Phase.WAITING and activate_on_enter:
		# Start beyond the doorway's thickness so closing it cannot trap the capsule.
		if trigger_bounds.grow(-7.0).has_point(subject):
			begin()
	if phase != Phase.ACTIVE:
		_previous_player = subject
		return
	_elapsed += delta
	_spawn_remaining -= delta
	if _spawn_remaining <= 0.0:
		_spawn_remaining += float(profile.get("spawn_interval"))
		for index: int in range(2 + difficulty_stage):
			_spawn_one()
	_routing_remaining -= delta
	if _routing_remaining <= 0.0:
		_routing_remaining = 0.25
		navigation.call("update_crowd", actors)
	_rebuild_buckets()
	# Snapshot: contact/parry/kill signals can remove actors during this step.
	for actor: Node2D in actors.duplicate():
		if phase != Phase.ACTIVE:
			break
		if not is_instance_valid(actor) or not bool(actor.call("is_alive")):
			continue
		_move_actor(actor as CharacterBody2D, subject, delta)
	_previous_player = subject


func viewport_bounds() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var view: Rect2 = get_viewport_rect()
	var area: Rect2 = Rect2(to_local(inverse * view.position), Vector2.ZERO)
	for corner: Vector2 in [view.end, Vector2(view.end.x, view.position.y), Vector2(view.position.x, view.end.y)]:
		area = area.expand(to_local(inverse * corner))
	return area


func _spawn_one() -> Node2D:
	if actors.size() >= int(profile.get("maximum_alive")) or phase != Phase.ACTIVE:
		return null
	var view: Rect2 = viewport_bounds()
	var outer: Rect2 = trigger_bounds.merge(view).grow(float(profile.get("spawn_margin")))
	var side: int = _spawn_sequence % 4
	_spawn_sequence += 1
	if arena_radius > 0.0:
		return _spawn_arena_spirit(view, side)
	var point: Vector2 = outer.get_center()
	var outward: Vector2 = Vector2.ZERO
	match side:
		0:
			point = Vector2(outer.position.x, _random.randf_range(outer.position.y, outer.end.y))
			outward = Vector2.LEFT
		1:
			point = Vector2(outer.end.x, _random.randf_range(outer.position.y, outer.end.y))
			outward = Vector2.RIGHT
		2:
			point = Vector2(_random.randf_range(outer.position.x, outer.end.x), outer.position.y)
			outward = Vector2.UP
		3:
			point = Vector2(_random.randf_range(outer.position.x, outer.end.x), outer.end.y)
			outward = Vector2.DOWN
	# Reject painted terrain and occupied spawn positions; never pop into the camera.
	var found: bool = false
	for attempt: int in range(96):
		var occupied: bool = false
		for other: Node2D in actors:
			if other.position.distance_squared_to(point) < SPACING * SPACING:
				occupied = true
				break
		var on_floor: bool = floor_query.is_valid() and bool(floor_query.call(to_global(point)))
		if not occupied and not on_floor and not view.grow(20.0).has_point(point):
			found = true
			break
		point += outward * 16.0
	if not found:
		return null
	return _create_spirit(point, view, side)


func _spawn_arena_spirit(view: Rect2, side: int) -> Node2D:
	var center: Vector2 = arena_center
	for attempt: int in range(96):
		var angle: float = float(side) * PI * 0.5 + _random.randf_range(-0.7, 0.7)
		var distance: float = arena_radius + float(profile.get("spawn_margin")) + floorf(float(attempt) / 8.0) * 16.0
		var point: Vector2 = center + Vector2.from_angle(angle) * distance
		if view.grow(20.0).has_point(point):
			continue
		var occupied: bool = false
		for other: Node2D in actors:
			if other.position.distance_squared_to(point) < SPACING * SPACING:
				occupied = true
				break
		if not occupied:
			return _create_spirit(point, view, side)
	return null


func _create_spirit(point: Vector2, view: Rect2, side: int) -> Node2D:
	var ghost: Node2D = GHOST.new() as Node2D
	ghost.name = "Spirit_%d" % _spawn_sequence
	ghost.position = point
	ghost.set("remains_system", remains_system)
	ghost.set_meta("spawn_position", point)
	ghost.set_meta("spawn_viewport", view)
	ghost.set_meta("spawn_side", side)
	ghost.set("phase", _random.randf_range(0.0, TAU))
	ghost.call("apply_profile", profile, difficulty_stage, true)
	add_child(ghost)
	ghost.reset_physics_interpolation()
	actors.append(ghost)
	ghost.connect("died", _on_killed)
	ghost.connect("consumed", _on_consumed)
	_route_deadlines[ghost.get_instance_id()] = _elapsed + _random.randf_range(0.0, 0.3)
	return ghost


func _rebuild_buckets() -> void:
	_buckets.clear()
	for actor: Node2D in actors:
		var bucket: Vector2i = Vector2i((actor.position / BUCKET).floor())
		if not _buckets.has(bucket):
			_buckets[bucket] = []
		(_buckets[bucket] as Array).append(actor)


func _separation(actor: Node2D) -> Vector2:
	var bucket: Vector2i = Vector2i((actor.position / BUCKET).floor())
	var correction: Vector2 = Vector2.ZERO
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			for other: Node2D in _buckets.get(bucket + Vector2i(x, y), []):
				if other == actor or not bool(other.call("is_alive")):
					continue
				var away: Vector2 = actor.position - other.position
				var distance: float = away.length()
				if distance < BUCKET and distance > 0.001:
					correction += away / distance * (1.0 - distance / BUCKET)
	return correction.limit_length(1.6)


func _move_actor(actor: CharacterBody2D, subject: Vector2, delta: float) -> void:
	var identifier: int = actor.get_instance_id()
	if _elapsed >= float(_route_deadlines.get(identifier, 0.0)) or not _waypoints.has(identifier):
		_waypoints[identifier] = navigation.call("waypoint", actor.position, subject)
		_route_deadlines[identifier] = _elapsed + 0.32
	var waypoint: Vector2 = _waypoints[identifier] as Vector2
	if actor.position.distance_squared_to(subject) < 72.0 * 72.0 or actor.position.distance_squared_to(waypoint) < 16.0 * 16.0:
		waypoint = subject
	var forward: Vector2 = actor.position.direction_to(waypoint)
	var distance: float = actor.position.distance_to(subject)
	var sway: float = float(actor.get("sway_strength"))
	var oscillation: float = sin(_elapsed * (2.0 + difficulty_stage * 0.65) + float(actor.get("phase")))
	var bend: float = sway * oscillation * clampf(distance / 80.0, 0.0, 1.0)
	var direction: Vector2 = (forward + forward.orthogonal() * bend).normalized()
	var speed: float = float(actor.get("movement_speed"))
	var impulse: Vector2 = actor.get("hit_velocity") as Vector2
	actor.set("hit_velocity", impulse * exp(-12.0 * delta))
	actor.velocity = (direction + _separation(actor) * 1.35).limit_length(1.0) * speed + impulse
	var previous: Vector2 = actor.position
	actor.move_and_slide()
	if arena_radius > 0.0 and _height_query.is_valid():
		(actor.get_node("Sprite") as Sprite2D).position.y = -7.0 - roundf(float(_height_query.call(actor.global_position)))
	# Swept relative motion also catches a moving player between physics frames.
	var relative_start: Vector2 = previous - (_previous_player + Vector2(0, 3))
	var relative_end: Vector2 = actor.position - (subject + Vector2(0, 3))
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2.ZERO, relative_start, relative_end)
	if closest.length_squared() > 11.0 * 11.0 or player.is_dashing():
		return
	if player.try_parry_enemy_attack(actor, player.global_position):
		return
	var health_before: float = player.health
	player.receive_contact_damage(int(actor.get("contact_damage")), actor.global_position.direction_to(player.global_position), 35.0)
	if player.health < health_before and not player.dead:
		player.apply_contact_slow(float(profile.get("contact_slow_factor")), float(profile.get("contact_slow_duration")), float(profile.get("post_slow_invulnerability")))
	actor.call("consume_on_contact")


func _forget(actor: Node2D) -> void:
	actors.erase(actor)
	_waypoints.erase(actor.get_instance_id())
	_route_deadlines.erase(actor.get_instance_id())


func _on_consumed(actor: Node2D) -> void:
	_forget(actor)


func _on_killed(actor: Node2D) -> void:
	_forget(actor)
	if phase != Phase.ACTIVE:
		return
	defeated_count += 1
	progress_changed.emit(defeated_count, kill_target)
	if defeated_count >= kill_target:
		_complete()
		return
	var next_stage: int = mini(int(defeated_count / 10.0), 3)
	if next_stage != difficulty_stage:
		difficulty_stage = next_stage
		for survivor: Node2D in actors:
			survivor.call("apply_profile", profile, difficulty_stage)
		stage_changed.emit(difficulty_stage)


func skip_to_completion() -> void:
	# Development shortcut: use the same completion signals as the final combat kill.
	if phase == Phase.CLEARED:
		return
	defeated_count = kill_target
	difficulty_stage = mini(int(maxi(kill_target - 1, 0) / 10.0), 3)
	progress_changed.emit(defeated_count, kill_target)
	_complete()


func _complete() -> void:
	phase = Phase.CLEARED
	# Dismiss remaining spirits without counting them as kills or spawning replacements.
	for survivor: Node2D in actors.duplicate():
		survivor.call("dismiss")
	gameplay.call("set_condition", clear_condition, true)
	gameplay.call("set_condition", entry_condition, true)
	_release_arena()
	cleared.emit()


func _release_arena() -> void:
	if arena_boundary != null:
		arena_boundary.call("set_active", false)
	if gameplay.has_meta(&"active_pedestal_encounter") and gameplay.get_meta(&"active_pedestal_encounter") == self:
		gameplay.remove_meta(&"active_pedestal_encounter")


func _on_player_defeated() -> void:
	if phase != Phase.ACTIVE:
		return
	phase = Phase.ABORTED
	_release_arena()
	for actor: Node2D in actors.duplicate():
		actor.call("dismiss")
	gameplay.call("set_condition", entry_condition, true)
	aborted.emit()
