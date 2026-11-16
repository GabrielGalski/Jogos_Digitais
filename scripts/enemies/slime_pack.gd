extends Node2D
signal cleared(pack: Node2D)
const ACTOR: Script = preload("res://scripts/enemies/slime.gd")
const JUMP_COORDINATOR: Script = preload("res://scripts/enemies/slime_jump_coordinator.gd")
var profile: SlimeProfile = preload("res://resources/enemies/slime/profile.tres")
var anchor: Vector2 = Vector2.ZERO
var target: Player = null
var members: Array[CharacterBody2D] = []
var neighbors: Array[Node2D] = []
var floor_query: Callable = Callable()
var height_query: Callable = Callable()
var remains_system: Node2D = null
var jump_coordinator: Node = null
var navigation: EnemyNavigationGrid = null
var anchor_leash: float = 224.0
var acquisition_range: float = 192.0
var suspended: bool = false
var engaged: bool = false
var _time: float = 0.0
var _acquire_at: float = 0.0
var _routes: Dictionary[int, PackedVector2Array] = {}
var _repath_at: Dictionary[int, float] = {}


func configure(center: Vector2, starts: Array[Vector2], subject: Player, _settings: FlyingEyeProfile,
		ground: Callable, height: Callable, leash: float, acquisition: float, seed_phase: float) -> void:
	anchor = center
	target = subject
	floor_query = ground
	height_query = height
	anchor_leash = minf(leash, 224.0)
	acquisition_range = acquisition
	y_sort_enabled = true
	for coordinator: Node in get_tree().get_nodes_in_group(&"slime_jump_coordinators"):
		if coordinator.get("target") == target: jump_coordinator = coordinator
	if jump_coordinator == null:
		jump_coordinator = JUMP_COORDINATOR.new()
		jump_coordinator.name = "SlimeJumpCoordinator"
		jump_coordinator.set("target", target)
		target.get_parent().add_child(jump_coordinator)
	for index: int in range(starts.size()):
		var actor: CharacterBody2D = ACTOR.new() as CharacterBody2D
		actor.name = "Slime_%d" % index
		actor.set("profile", profile)
		actor.set("player", target)
		actor.set("squad", self)
		actor.set("jump_coordinator", jump_coordinator)
		actor.set("remains_system", remains_system)
		actor.set("height_query", height_query)
		actor.set("home_position", starts[index])
		actor.set("phase", seed_phase + index * 1.71)
		actor.set("floor_height", float(height_query.call(starts[index])) if height_query.is_valid() else 0.0)
		actor.position = to_local(starts[index])
		add_child(actor)
		actor.reset_physics_interpolation()
		actor.connect("died", _on_member_died)
		members.append(actor)


func _physics_process(delta: float) -> void:
	_time += delta
	if members.is_empty():
		if get_child_count() == 0: queue_free()
		return
	if not is_instance_valid(target): return
	var distance: float = anchor.distance_to(target.global_position)
	if suspended or target.dead or target.intro_locked or distance > anchor_leash:
		_set_engaged(false)
	elif not engaged and distance <= acquisition_range and _time >= _acquire_at:
		_acquire_at = _time + 0.45
		_ensure_navigation()
		if not navigation.find_path(anchor, target.global_position).is_empty(): _set_engaged(true)
	for actor: CharacterBody2D in members: actor.set("neighbors", neighbors)


func _set_engaged(value: bool) -> void:
	if engaged == value: return
	engaged = value
	for actor: CharacterBody2D in members: actor.call("set_engaged", value)


func set_suspended(value: bool) -> void:
	suspended = value
	if value: _set_engaged(false)


func _ensure_navigation() -> void:
	if navigation != null: return
	navigation = EnemyNavigationGrid.new()
	navigation.cell_size = 16.0
	var reach: float = anchor_leash + 48.0
	navigation.build(get_world_2d(), Rect2(anchor - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), profile.body_radius, 1)
	if floor_query.is_valid():
		for y: int in range(navigation.grid.region.size.y):
			for x: int in range(navigation.grid.region.size.x):
				var cell: Vector2i = Vector2i(x, y)
				if not navigation.grid.is_point_solid(cell) and not bool(floor_query.call(navigation.grid.get_point_position(cell))):
					navigation.grid.set_point_solid(cell, true)


func steer(actor: CharacterBody2D, requested: Vector2) -> Vector2:
	_ensure_navigation()
	var goal: Vector2 = anchor + (requested - anchor).limit_length(anchor_leash - 12.0)
	var direction: Vector2 = Vector2.ZERO
	if actor.global_position.distance_to(goal) > 4.0:
		if navigation.corridor_clear(actor.global_position, goal): direction = actor.global_position.direction_to(goal)
		else:
			var identifier: int = actor.get_instance_id()
			if _time >= float(_repath_at.get(identifier, 0.0)):
				_routes[identifier] = navigation.find_path(actor.global_position, goal)
				_repath_at[identifier] = _time + 0.55 + fmod(float(actor.get("phase")), 0.10)
			var route: PackedVector2Array = _routes.get(identifier, PackedVector2Array()) as PackedVector2Array
			while not route.is_empty() and actor.global_position.distance_to(route[0]) < 6.0: route.remove_at(0)
			_routes[identifier] = route
			if not route.is_empty(): direction = actor.global_position.direction_to(route[0])
	var separation: Vector2 = Vector2.ZERO
	for other: Node2D in neighbors:
		if not is_instance_valid(other) or other == actor: continue
		var offset: Vector2 = actor.global_position - other.global_position
		var radius: float = float(other.call("get_separation_radius")) if other.has_method("get_separation_radius") else 7.0
		var space: float = radius + profile.body_radius + 4.0
		var distance: float = offset.length()
		if distance > 0.01 and distance < space: separation += offset / distance * (1.0 - distance / space)
	return (direction + separation.limit_length(1.0) * 1.4).limit_length(1.0)


func _on_member_died(actor: Node2D) -> void:
	members.erase(actor)
	_routes.erase(actor.get_instance_id())
	_repath_at.erase(actor.get_instance_id())
	if members.is_empty(): cleared.emit(self)


func dismiss() -> void:
	for actor: CharacterBody2D in members.duplicate(): actor.call("dismiss")
	members.clear()
	queue_free()
