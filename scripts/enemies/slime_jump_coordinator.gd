extends Node
## Scene-owned jump queue shared by every Slime pack targeting the same player.
const MAX_RESERVATIONS: int = 2
const TAKEOFF_GAP: float = 0.12
const REQUEST_GAP: float = 0.16
var target: Player = null
var reservations: Dictionary[int, Dictionary] = {}
var _waiting: Array[WeakRef] = []
var _clock: float = 0.0
var _airborne: int = 0
var _takeoff_after: float = 0.0
var _request_after: float = 0.0


func _ready() -> void:
	process_physics_priority = -10
	add_to_group(&"slime_jump_coordinators")


func _physics_process(delta: float) -> void:
	_clock += delta
	for identifier: int in reservations.keys():
		var actor: Node2D = (reservations[identifier].actor as WeakRef).get_ref() as Node2D
		if not _eligible(actor): _release_id(identifier)
	for index: int in range(_waiting.size() - 1, -1, -1):
		var actor: Node2D = _waiting[index].get_ref() as Node2D
		if not _eligible(actor) or not bool(actor.call("can_queue_jump")): _waiting.remove_at(index)


func _eligible(actor: Node2D) -> bool:
	return is_instance_valid(actor) and bool(actor.call("is_alive")) and bool(actor.get("engaged"))


func request(actor: CharacterBody2D, preferred: Vector2) -> Dictionary:
	var identifier: int = actor.get_instance_id()
	if reservations.has(identifier): return reservations[identifier]
	var queued: bool = false
	for reference: WeakRef in _waiting:
		if reference.get_ref() == actor: queued = true
	if not queued: _waiting.append(weakref(actor))
	if reservations.size() >= MAX_RESERVATIONS or _clock < _request_after or _waiting[0].get_ref() != actor: return {}
	var goal: Dictionary = _pick_goal(actor, preferred)
	if goal.is_empty():
		_waiting.pop_front()
		return {}
	reservations[identifier] = {"actor": weakref(actor), "goal": goal.point, "launched": false}
	_waiting.pop_front()
	_request_after = _clock + REQUEST_GAP
	return reservations[identifier]


func refresh(actor: CharacterBody2D, preferred: Vector2) -> Vector2:
	var identifier: int = actor.get_instance_id()
	if not reservations.has(identifier): return actor.global_position
	var entry: Dictionary = reservations[identifier]
	if not bool(entry.launched):
		var goal: Dictionary = _pick_goal(actor, preferred)
		if not goal.is_empty(): entry.goal = goal.point
	return entry.goal as Vector2


func _pick_goal(actor: CharacterBody2D, preferred: Vector2) -> Dictionary:
	var away: Vector2 = preferred.direction_to(actor.global_position)
	if away.is_zero_approx(): away = Vector2.RIGHT
	var candidates: Array[Vector2] = [preferred + away * 18.0]
	for angle: float in [PI / 3.0, -PI / 3.0, PI * 2.0 / 3.0, -PI * 2.0 / 3.0, PI]:
		candidates.append(preferred + away.rotated(angle) * 20.0)
	var radius: float = float(actor.call("get_separation_radius"))
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius + 1.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = 4
	query.exclude = [actor.get_rid()]
	for identifier: int in reservations:
		var other: CharacterBody2D = (reservations[identifier].actor as WeakRef).get_ref() as CharacterBody2D
		if is_instance_valid(other) and bool(reservations[identifier].launched): query.exclude.append(other.get_rid())
	for point: Vector2 in candidates:
		if not bool(actor.call("_landing_valid", point)): continue
		var free: bool = true
		for identifier: int in reservations:
			if identifier == actor.get_instance_id(): continue
			var other: Node2D = (reservations[identifier].actor as WeakRef).get_ref() as Node2D
			if not is_instance_valid(other): continue
			var clearance: float = radius + float(other.call("get_separation_radius")) + 6.0
			if point.distance_to(reservations[identifier].goal as Vector2) < clearance: free = false
		if not free: continue
		query.transform = Transform2D(0, point)
		if actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): return {"point": point}
	return {}


func can_takeoff(actor: Node2D) -> bool:
	var identifier: int = actor.get_instance_id()
	if not reservations.has(identifier) or _airborne != 0 or _clock < _takeoff_after: return false
	# Keep the request order when a second Slime is preparing behind the current jump.
	for other_id: int in reservations:
		if other_id == identifier: return true
		if not bool(reservations[other_id].launched): return false
	return false


func takeoff(actor: Node2D) -> void:
	var identifier: int = actor.get_instance_id()
	if not can_takeoff(actor): return
	reservations[identifier].launched = true
	_airborne = identifier


func landed(actor: Node2D) -> void:
	if _airborne == actor.get_instance_id():
		_airborne = 0
		_takeoff_after = _clock + TAKEOFF_GAP


func release(actor: Node2D) -> void:
	_release_id(actor.get_instance_id())
	for index: int in range(_waiting.size() - 1, -1, -1):
		if _waiting[index].get_ref() == actor: _waiting.remove_at(index)


func _release_id(identifier: int) -> void:
	reservations.erase(identifier)
	if _airborne == identifier:
		_airborne = 0
		_takeoff_after = _clock + TAKEOFF_GAP
