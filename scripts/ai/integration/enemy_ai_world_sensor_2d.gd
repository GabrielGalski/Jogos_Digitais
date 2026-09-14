class_name EnemyAIWorldSensor2D
extends Node
## Persistent routing over a shared static map; bounded local sensing for moving actors.

@export_flags_2d_physics var obstacle_mask: int = 1
@export var neighbor_detection_radius: float = 72.0
@export var max_neighbors: int = 12
@export var attack_slot_radius: float = 2.0
@export var target_offset: Vector2 = Vector2(0.0, 3.0)
@export var repath_interval: float = 0.6
@export var target_repath_distance: float = 24.0
@export var stuck_timeout: float = 1.0
@export var actor_role: int = EnemyAIEnums.Role.ELITE

var navigation: EnemyNavigationGrid
var route: PackedVector2Array = PackedVector2Array()
var waypoint: int = 0
var replans: int = 0
var _chamber: Node2D
var _bounds: Rect2
var _last_goal: Vector2 = Vector2.INF
var _repath_left: float = 0.0
var _stuck_time: float = 0.0
var _progress_origin: Vector2 = Vector2.INF
var _neighbors_left: float = 0.0
var _neighbors: Array[EnemyAINeighbor] = []
var _revision: int = -1
var _blockers: Array[Vector3] = []
var _target_rid: RID


func configure(chamber: Node2D, world_bounds: Rect2) -> void:
	_chamber = chamber
	_bounds = world_bounds
	navigation = null
	reset_route()


func reset_route() -> void:
	route.clear()
	_blockers.clear()
	waypoint = 0
	_last_goal = Vector2.INF
	_repath_left = 0.0
	_stuck_time = 0.0
	_progress_origin = Vector2.INF


func build_observation(actor: CharacterBody2D, target: CharacterBody2D,
		objective: int, preferred_attack_distance: float,
		landing_position_valid: bool, delta: float = 0.016667) -> EnemyAIObservation:
	var observation: EnemyAIObservation = EnemyAIObservation.new()
	observation.actor_id = StringName(str(actor.get_instance_id()))
	observation.self_position = actor.global_position
	observation.self_radius = _body_radius(actor)
	observation.objective = objective
	observation.chamber_active = objective != EnemyAIEnums.Objective.DISABLED
	observation.landing_position_valid = landing_position_valid
	observation.target_valid = is_instance_valid(target) and target.is_inside_tree()
	if not observation.target_valid or not observation.chamber_active:
		reset_route()
		observation.refresh_distance()
		return observation
	_target_rid = target.get_rid()
	_ensure_navigation(actor, observation.self_radius)
	observation.target_position = target.global_position + target_offset
	observation.target_velocity = target.velocity
	observation.line_of_sight_clear = _has_line_of_sight(actor, target, observation.target_position)
	# Perception is chamber based; a hole blocks walking/melee, not awareness of Nox.
	observation.target_visible = true
	observation.refresh_distance()
	observation.route_direction = _follow_route(actor, observation.target_position, delta)
	observation.route_valid = waypoint < route.size()
	observation.target_reachable = observation.route_valid or (
		observation.line_of_sight_clear and observation.distance_to_target <= preferred_attack_distance)
	observation.has_fallback_position = observation.route_valid
	observation.fallback_position = route[waypoint] if observation.route_valid else actor.global_position
	_neighbors_left -= delta
	if _neighbors_left <= 0.0:
		_neighbors_left = 0.12
		_neighbors = _collect_neighbors(actor)
	observation.neighbors = _neighbors
	# Contact attacks need unobstructed access, never just Euclidean distance through a wall.
	var from_target: Vector2 = (actor.global_position - observation.target_position).normalized()
	var slot_position: Vector2 = observation.target_position + from_target * preferred_attack_distance
	var slot: EnemyAISlot = EnemyAISlot.new(observation.actor_id, slot_position, attack_slot_radius, actor_role)
	for neighbor: EnemyAINeighbor in _neighbors:
		if neighbor.is_attacking and neighbor.position.distance_to(slot_position) < neighbor.radius + observation.self_radius:
			slot.occupied_by = neighbor.actor_id
			break
	observation.attack_slots.append(slot)
	return observation


func _ensure_navigation(actor: CharacterBody2D, radius: float) -> void:
	assert(_chamber != null, "Configure the sensor with chamber bounds before use.")
	var key: StringName = StringName("enemy_navigation_%s_%s" % [ceili(radius), obstacle_mask])
	if navigation == null:
		if not _chamber.has_meta(key):
			_chamber.set_meta(key, EnemyNavigationGrid.new())
		navigation = _chamber.get_meta(key) as EnemyNavigationGrid
	if not navigation.ready:
		navigation.build(actor.get_world_2d(), _bounds, ceilf(radius), obstacle_mask)
	if _revision != navigation.revision:
		reset_route()
		_revision = navigation.revision


func _follow_route(actor: CharacterBody2D, goal: Vector2, delta: float) -> Vector2:
	_repath_left = maxf(0.0, _repath_left - delta)
	if _progress_origin == Vector2.INF or actor.global_position.distance_to(_progress_origin) > 6.0:
		_progress_origin = actor.global_position
		_stuck_time = 0.0
	elif actor.global_position.distance_to(goal) > 32.0:
		_stuck_time += delta
	var changed_goal: bool = _last_goal == Vector2.INF or goal.distance_to(_last_goal) >= target_repath_distance
	if _repath_left <= 0.0 and (changed_goal or route.is_empty() or _stuck_time >= stuck_timeout or not _blockers.is_empty()):
		if _stuck_time >= stuck_timeout or not _blockers.is_empty():
			_blockers = _congestion(actor)
		route = navigation.find_path(actor.global_position, goal, _blockers)
		waypoint = 0
		_last_goal = goal
		_stuck_time = 0.0
		_repath_left = repath_interval
		replans += 1
	if route.is_empty():
		return Vector2.ZERO
	while waypoint < route.size() and actor.global_position.distance_to(route[waypoint]) <= 3.0:
		waypoint += 1
	# Keep the selected side of the obstacle. Only skip waypoints when the entire
	# segment has clearance; no left/right direction guessing on successive ticks.
	while waypoint + 1 < route.size() and _corridor_clear(actor.global_position, route[waypoint + 1]):
		waypoint += 1
	if waypoint >= route.size():
		if _corridor_clear(actor.global_position, goal):
			return actor.global_position.direction_to(goal)
		return Vector2.ZERO
	return actor.global_position.direction_to(route[waypoint])


func safe_velocity(actor: CharacterBody2D, desired: Vector2, delta: float) -> Vector2:
	if desired.is_zero_approx():
		return Vector2.ZERO
	# Preserve the global route if separation would push the actor into an obstacle.
	if not actor.test_move(actor.global_transform, desired * maxf(delta, 0.08)):
		return desired
	if waypoint < route.size():
		var routed: Vector2 = actor.global_position.direction_to(route[waypoint]) * desired.length()
		if not actor.test_move(actor.global_transform, routed * maxf(delta, 0.08)):
			return routed
		# A deterministic side preference avoids symmetric crowd deadlock.
		for angle: float in [0.6, -0.6, 1.1, -1.1]:
			var candidate: Vector2 = routed.rotated(angle)
			if navigation.corridor_clear(actor.global_position, actor.global_position + candidate * 0.15) and not actor.test_move(actor.global_transform, candidate * 0.15):
				return candidate * 0.65
	return Vector2.ZERO


func _has_line_of_sight(actor: CharacterBody2D, target: CharacterBody2D, target_position: Vector2) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(actor.global_position, target_position, obstacle_mask)
	query.exclude = [actor.get_rid(), target.get_rid()]
	return actor.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _collect_neighbors(actor: CharacterBody2D) -> Array[EnemyAINeighbor]:
	var neighbors: Array[EnemyAINeighbor] = []
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = neighbor_detection_radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, actor.global_position)
	query.exclude = [actor.get_rid()]
	var seen: Dictionary = {}
	for hit: Dictionary in actor.get_world_2d().direct_space_state.intersect_shape(query, 48):
		var candidate: Node2D = hit["collider"] as Node2D
		if candidate == null or not candidate.is_in_group(&"enemy_ai_actor") or seen.has(candidate.get_instance_id()):
			continue
		seen[candidate.get_instance_id()] = true
		var neighbor: EnemyAINeighbor = EnemyAINeighbor.new(StringName(str(candidate.get_instance_id())), candidate.global_position, _body_radius(candidate))
		neighbor.is_attacking = bool(candidate.get_meta(&"enemy_ai_is_attacking", false))
		neighbor.is_elite = bool(candidate.get_meta(&"enemy_ai_is_elite", false))
		neighbors.append(neighbor)
	neighbors.sort_custom(func(a: EnemyAINeighbor, b: EnemyAINeighbor) -> bool:
		return actor.global_position.distance_squared_to(a.position) < actor.global_position.distance_squared_to(b.position))
	if neighbors.size() > max_neighbors:
		neighbors.resize(max_neighbors)
	return neighbors


func _body_radius(body: Node2D) -> float:
	var collision: CollisionShape2D = body.get_node_or_null("BodyCollision") as CollisionShape2D
	if collision != null and collision.shape is CircleShape2D:
		return (collision.shape as CircleShape2D).radius * maxf(absf(body.global_scale.x), absf(body.global_scale.y))
	return 8.0

func _congestion(actor: CharacterBody2D) -> Array[Vector3]:
	var blockers: Array[Vector3] = []
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 200.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, actor.global_position)
	query.exclude = [actor.get_rid(), _target_rid]
	var seen: Dictionary = {}
	for hit: Dictionary in actor.get_world_2d().direct_space_state.intersect_shape(query, 128):
		var body: CharacterBody2D = hit["collider"] as CharacterBody2D
		if body == null or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		blockers.append(Vector3(body.global_position.x, body.global_position.y, _body_radius(actor) + _body_radius(body) + 2.0))
	return blockers


func _corridor_clear(from: Vector2, to: Vector2) -> bool:
	if not navigation.corridor_clear(from, to):
		return false
	for blocker: Vector3 in _blockers:
		var center: Vector2 = Vector2(blocker.x, blocker.y)
		if Geometry2D.get_closest_point_to_segment(center, from, to).distance_to(center) < blocker.z:
			return false
	return true
