extends Node2D
## Anchored mixed encounter. Only flies share an attack turn; littles act alone.
signal cleared(pack: Node2D)

const ACTOR: Script = preload("res://scripts/enemies/insects/insect_actor.gd")
const PROFILES: Dictionary[StringName, InsectProfile] = {
	&"tall": preload("res://resources/enemies/insects/tall.tres"),
	&"fly": preload("res://resources/enemies/insects/fly.tres"),
	&"little": preload("res://resources/enemies/insects/little.tres"),
}
enum State { IDLE, ENGAGED, RETURNING }
var anchor: Vector2 = Vector2.ZERO
var target: Player = null
var members: Array[InsectActor] = []
var neighbors: Array[Node2D] = []
var composition: Array[StringName] = []
var state: State = State.IDLE
var suspended: bool = false
var anchor_leash: float = 280.0
var acquisition_range: float = 192.0
var floor_query: Callable = Callable()
var height_query: Callable = Callable()
var remains_system: Node2D = null
var palette_variant: int = 0
var navigation: EnemyNavigationGrid = null
var fly_attacker: InsectActor = null
var fly_turn_log: Array[Dictionary] = []
var _routes: Dictionary[int, PackedVector2Array] = {}
var _repath_at: Dictionary[int, float] = {}
var _time: float = 0.0
var _acquire_at: float = 0.0
var _fly_cursor: int = 0


func configure(center: Vector2, starts: Array[Vector2], kinds: Array[StringName], subject: Player,
		ground: Callable, height: Callable, leash: float, acquisition: float, seed_phase: float,
		remains: Node2D = null) -> void:
	anchor = center
	target = subject
	composition = kinds.duplicate()
	floor_query = ground
	height_query = height
	remains_system = remains
	anchor_leash = leash
	acquisition_range = acquisition
	y_sort_enabled = true
	for index: int in range(starts.size()):
		var actor: InsectActor = ACTOR.new() as InsectActor
		actor.name = "%s_%d" % [kinds[index].capitalize(), index]
		actor.profile = PROFILES[kinds[index]]
		actor.player = target
		actor.squad = self
		actor.remains_system = remains_system
		actor.palette_variant = palette_variant
		actor.height_query = height_query
		actor.floor_height = float(height_query.call(starts[index])) if height_query.is_valid() else 0.0
		actor.home_position = starts[index]
		actor.phase = seed_phase + index * 1.71
		actor.orbit_sign = 1.0 if index % 2 == 0 else -1.0
		actor.position = to_local(starts[index])
		add_child(actor)
		actor.reset_physics_interpolation()
		actor.died.connect(_on_member_died)
		members.append(actor)


func _physics_process(delta: float) -> void:
	_time += delta
	if members.is_empty():
		# A dying actor must finish its authored animation before the pack disappears.
		if get_child_count() == 0: queue_free()
		return
	if not is_instance_valid(target): return
	var distance: float = anchor.distance_to(target.global_position)
	if target.dead or target.intro_locked or suspended or distance > anchor_leash:
		if state == State.ENGAGED: _disengage()
	elif state == State.IDLE and distance <= acquisition_range and _time >= _acquire_at:
		_acquire_at = _time + 0.45
		_ensure_navigation()
		if not navigation.find_path(anchor, target.global_position).is_empty():
			state = State.ENGAGED
			for actor: InsectActor in members: actor.set_engaged(true)
	if state == State.ENGAGED:
		if not is_instance_valid(fly_attacker) or not fly_attacker.can_take_fly_turn():
			_choose_fly(null, &"ready")
	var arrived: bool = true
	for actor: InsectActor in members:
		actor.neighbors = neighbors
		if actor.global_position.distance_to(actor.home_position) > 6.0: arrived = false
	if state == State.RETURNING and arrived: state = State.IDLE


func set_suspended(value: bool) -> void:
	if suspended == value: return
	suspended = value
	if value: _disengage()
	for actor: InsectActor in members: actor.suspended = value


func _disengage() -> void:
	state = State.RETURNING
	fly_attacker = null
	for actor: InsectActor in members: actor.set_engaged(false)


func _ensure_navigation() -> void:
	if navigation != null: return
	navigation = EnemyNavigationGrid.new()
	navigation.cell_size = 8.0
	var reach: float = anchor_leash + 64.0
	var clearance: float = 6.0
	for actor: InsectActor in members: clearance = maxf(clearance, actor.profile.body_radius)
	navigation.build(get_world_2d(), Rect2(anchor - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), clearance, 1)
	# Floor support is explicit: never path through rivers or void, even without walls.
	if floor_query.is_valid():
		for y: int in range(navigation.grid.region.size.y):
			for x: int in range(navigation.grid.region.size.x):
				var cell: Vector2i = Vector2i(x, y)
				if not navigation.grid.is_point_solid(cell) and not bool(floor_query.call(navigation.grid.get_point_position(cell))):
					navigation.grid.set_point_solid(cell, true)


func steer(actor: InsectActor, requested_goal: Vector2, curve: float = 0.0) -> Vector2:
	var goal: Vector2 = anchor + (requested_goal - anchor).limit_length(anchor_leash - 16.0)
	var direction: Vector2 = Vector2.ZERO
	if actor.global_position.distance_to(goal) > 3.0:
		_ensure_navigation()
		if navigation.corridor_clear(actor.global_position, goal):
			direction = actor.global_position.direction_to(goal)
		else:
			var identifier: int = actor.get_instance_id()
			if _time >= float(_repath_at.get(identifier, 0.0)):
				_routes[identifier] = navigation.find_path(actor.global_position, goal)
				_repath_at[identifier] = _time + 0.42 + fmod(actor.phase, 0.15)
			var route: PackedVector2Array = _routes.get(identifier, PackedVector2Array()) as PackedVector2Array
			while not route.is_empty() and actor.global_position.distance_to(route[0]) < 5.0: route.remove_at(0)
			_routes[identifier] = route
			if not route.is_empty(): direction = actor.global_position.direction_to(route[0])
	if not direction.is_zero_approx() and not is_zero_approx(curve):
		var curved: Vector2 = direction.rotated(curve)
		# Weave only inside the navigable corridor; A* still owns walls and river edges.
		if navigation.corridor_clear(actor.global_position, actor.global_position + curved * 24.0):
			direction = curved
	var separation: Vector2 = Vector2.ZERO
	for other: Node2D in neighbors:
		if not is_instance_valid(other) or other == actor: continue
		var offset_to_other: Vector2 = actor.global_position - other.global_position
		var distance: float = offset_to_other.length()
		if distance > 30.0: continue
		var radius: float = float(other.call("get_separation_radius")) if other.has_method("get_separation_radius") else 7.0
		var space: float = actor.profile.body_radius + radius + 4.0
		if distance > 0.01 and distance < space:
			separation += offset_to_other / distance * (1.0 - distance / space)
	return (direction + separation.limit_length(1.2) * 1.6).limit_length(1.0)


func yield_fly_turn(actor: InsectActor, reason: StringName) -> void:
	if fly_attacker == actor:
		fly_attacker = null
		_choose_fly(actor, reason)


func _choose_fly(excluded: InsectActor, reason: StringName) -> void:
	if state != State.ENGAGED or suspended or members.is_empty():
		fly_attacker = null
		return
	for offset: int in range(members.size()):
		var index: int = (_fly_cursor + offset) % members.size()
		var candidate: InsectActor = members[index]
		if candidate == excluded or not candidate.can_take_fly_turn(): continue
		fly_attacker = candidate
		_fly_cursor = (index + 1) % members.size()
		if fly_turn_log.size() < 128: fly_turn_log.append({"actor": candidate.get_instance_id(), "reason": reason, "time": _time})
		return
	fly_attacker = null


func _on_member_died(actor: Node2D) -> void:
	var was_attacker: bool = actor == fly_attacker
	members.erase(actor)
	_routes.erase(actor.get_instance_id())
	_repath_at.erase(actor.get_instance_id())
	if was_attacker:
		fly_attacker = null
		_choose_fly(null, &"attacker_died")
	if members.is_empty(): cleared.emit(self)


func dismiss() -> void:
	fly_attacker = null
	for actor: InsectActor in members.duplicate():
		if is_instance_valid(actor): actor.dismiss()
	members.clear()
	queue_free()
