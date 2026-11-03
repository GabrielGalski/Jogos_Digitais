extends Node2D
## One anchored pack owns formation slots and exactly one three-shot attack token.
signal shot_requested(actor: Node2D, heading: Vector2, pack: Node2D)
signal cleared(pack: Node2D)

const ACTOR: Script = preload("res://scripts/enemies/flying_eye.gd")
const AFFILIATION: Script = preload("res://scripts/combat/combat_affiliation.gd")
enum State { IDLE, ENGAGED, RETURNING }
enum Attack { READY, WINDUP, VOLLEY }
var profile: FlyingEyeProfile
var anchor: Vector2 = Vector2.ZERO
var target: Player = null
var members: Array[CharacterBody2D] = []
var neighbors: Array[Node2D] = []
var state: State = State.IDLE
var suspended: bool = false
var anchor_leash: float = 264.0
var acquisition_range: float = 192.0
var navigation: EnemyNavigationGrid = null
var floor_query: Callable = Callable()
var height_query: Callable = Callable()
var shots_fired: int = 0
var attack_log: Array[Dictionary] = []
var _attack: Attack = Attack.READY
var _attacker: CharacterBody2D = null
var _turn_cursor: int = 0
var _attack_left: float = 0.65
var _shots_in_turn: int = 0
var _locked_aim: Vector2 = Vector2.ZERO
var _slot_phase: float = 0.0
var _slot_order: Dictionary[int, int] = {}
var _routes: Dictionary[int, PackedVector2Array] = {}
var _repath_at: Dictionary[int, float] = {}
var _time: float = 0.0
var _empty_age: float = 0.0
var _acquire_at: float = 0.0


func configure(center: Vector2, starts: Array[Vector2], player: Player, settings: FlyingEyeProfile,
		ground: Callable, height: Callable, leash: float, acquisition: float, seed_phase: float) -> void:
	anchor = center
	target = player
	profile = settings
	floor_query = ground
	height_query = height
	anchor_leash = leash
	acquisition_range = acquisition
	y_sort_enabled = true
	_slot_phase = seed_phase
	for index: int in range(starts.size()):
		var eye: CharacterBody2D = ACTOR.new() as CharacterBody2D
		eye.name = "FlyingEye_%d" % index
		eye.set("profile", profile)
		eye.set("height_query", height_query)
		eye.set("floor_height", float(height_query.call(starts[index])) if height_query.is_valid() else 0.0)
		eye.set("phase", seed_phase + index * 1.7)
		eye.set("home_position", starts[index])
		add_child(eye)
		eye.global_position = starts[index]
		eye.reset_physics_interpolation()
		eye.connect("died", _on_member_died)
		members.append(eye)


func set_suspended(value: bool) -> void:
	if suspended == value: return
	suspended = value
	if suspended:
		_stop_attack()
		state = State.RETURNING


func _ensure_navigation() -> void:
	if navigation != null: return
	navigation = EnemyNavigationGrid.new()
	navigation.cell_size = profile.navigation_cell_size
	var reach: float = anchor_leash + 48.0
	navigation.build(get_world_2d(), Rect2(anchor - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), profile.body_radius, 1)


func _physics_process(delta: float) -> void:
	_time += delta
	if members.is_empty():
		_empty_age += delta
		if _empty_age > 0.75: queue_free()
		return
	if not is_instance_valid(target): return
	var anchor_distance: float = anchor.distance_to(target.global_position)
	if target.dead or target.intro_locked or suspended or anchor_distance > anchor_leash:
		if state == State.ENGAGED:
			_stop_attack()
			state = State.RETURNING
	elif state == State.IDLE and anchor_distance <= acquisition_range and _time >= _acquire_at and AFFILIATION.can_damage(&"monsters", target):
		_acquire_at = _time + 0.45
		_ensure_navigation()
		# Do not activate from the opposite bank of an unreachable river.
		if not navigation.find_path(anchor, target.global_position).is_empty():
			state = State.ENGAGED
			_slot_phase = (anchor - target.global_position).angle() + fmod(_slot_phase, 0.4)
			_assign_slots()
			_attack_left = 0.65
	var arrived: bool = true
	for member: CharacterBody2D in members:
		if not is_instance_valid(member) or not bool(member.call("is_alive")): continue
		var goal: Vector2 = _slot_goal(member) if state == State.ENGAGED else member.get("home_position") as Vector2
		if state != State.ENGAGED and member.global_position.distance_to(goal) > 4.0: arrived = false
		_drive(member, goal, delta)
		if state == State.ENGAGED: member.call("aim", member.global_position.direction_to(target.global_position), member == _attacker)
	if state == State.RETURNING and arrived:
		state = State.IDLE
	if state == State.ENGAGED:
		_slot_phase += delta * 0.035
		_update_attack(delta)


func _assign_slots() -> void:
	_slot_order.clear()
	var ordered: Array[CharacterBody2D] = members.duplicate()
	ordered.sort_custom(func(a: CharacterBody2D, b: CharacterBody2D) -> bool:
		return (a.global_position - target.global_position).angle() < (b.global_position - target.global_position).angle())
	var best_shift: int = 0
	var best_cost: float = INF
	for shift: int in range(ordered.size()):
		var cost: float = 0.0
		for index: int in range(ordered.size()):
			var angle: float = _slot_phase + TAU * float((index + shift) % ordered.size()) / ordered.size()
			cost += ordered[index].global_position.distance_squared_to(target.global_position + Vector2.from_angle(angle) * profile.preferred_distance)
		if cost < best_cost:
			best_cost = cost
			best_shift = shift
	for index: int in range(ordered.size()): _slot_order[ordered[index].get_instance_id()] = (index + best_shift) % ordered.size()


func _slot_goal(member: CharacterBody2D) -> Vector2:
	var slot: int = int(_slot_order.get(member.get_instance_id(), 0))
	var radius: float = profile.preferred_distance + float(members.size() - 2) * 3.0
	var angle: float = _slot_phase + TAU * float(slot) / maxi(members.size(), 1)
	var goal: Vector2 = target.global_position + Vector2.from_angle(angle) * radius
	var radial: Vector2 = target.global_position.direction_to(member.global_position)
	var distance: float = member.global_position.distance_to(target.global_position)
	var angular_error: float = radial.angle_to(Vector2.from_angle(angle))
	if distance < radius * 1.3 and absf(angular_error) > 0.3:
		# Travel around Nox rather than cutting straight through the ring.
		goal = member.global_position + radial.rotated(signf(angular_error) * PI * 0.5) * 48.0 + radial * (radius - distance)
	if distance < profile.retreat_distance:
		goal = member.global_position + radial * 42.0 + radial.rotated(signf(angular_error) * PI * 0.5) * 24.0
	return anchor + (goal - anchor).limit_length(anchor_leash - 16.0)


func _separation(member: CharacterBody2D) -> Vector2:
	var result: Vector2 = Vector2.ZERO
	for other: Node2D in neighbors:
		if not is_instance_valid(other) or other == member: continue
		var offset: Vector2 = member.global_position - other.global_position
		var distance: float = offset.length()
		if distance > 32.0: continue
		var other_radius: float = float(other.call("get_separation_radius")) if other.has_method("get_separation_radius") else 8.0
		var personal_space: float = profile.body_radius + other_radius + 5.0
		if distance > 0.01 and distance < personal_space:
			result += offset / distance * (1.0 - distance / personal_space)
	return result.limit_length(1.25)


func _drive(member: CharacterBody2D, goal: Vector2, _delta: float) -> void:
	if member == _attacker:
		member.set("desired_velocity", Vector2.ZERO)
		return
	var direction: Vector2 = Vector2.ZERO
	if member.global_position.distance_to(goal) > 3.0:
		_ensure_navigation()
		if navigation.corridor_clear(member.global_position, goal):
			direction = member.global_position.direction_to(goal)
		else:
			var identifier: int = member.get_instance_id()
			if _time >= float(_repath_at.get(identifier, 0.0)):
				_routes[identifier] = navigation.find_path(member.global_position, goal)
				_repath_at[identifier] = _time + 0.65
			var route: PackedVector2Array = _routes.get(identifier, PackedVector2Array()) as PackedVector2Array
			while not route.is_empty() and member.global_position.distance_to(route[0]) < 6.0: route.remove_at(0)
			_routes[identifier] = route
			if not route.is_empty(): direction = member.global_position.direction_to(route[0])
	var separation: Vector2 = _separation(member)
	member.set("desired_velocity", (direction + separation * 1.6).limit_length(1.0) * profile.movement_speed)
	if state != State.ENGAGED and not direction.is_zero_approx(): member.call("aim", direction, false)


func _line_clear(member: CharacterBody2D) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(member.global_position, target.global_position, 1)
	query.exclude = [member.get_rid(), target.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _update_attack(delta: float) -> void:
	_attack_left -= delta
	if _attack_left > 0.0: return
	if _attack == Attack.READY:
		for offset: int in range(members.size()):
			var index: int = (_turn_cursor + offset) % members.size()
			var candidate: CharacterBody2D = members[index]
			var distance: float = candidate.global_position.distance_to(target.global_position)
			if distance < profile.retreat_distance or distance > minf(profile.attack_range, profile.preferred_distance + 38.0) or not _line_clear(candidate): continue
			_attacker = candidate
			_turn_cursor = index
			_attacker.set_meta(&"enemy_ai_is_attacking", true)
			_attacker.call("aim", _attacker.global_position.direction_to(target.global_position), true)
			_attack = Attack.WINDUP
			_attack_left = profile.windup
			_shots_in_turn = 0
			return
		_attack_left = 0.2
		return
	if not is_instance_valid(_attacker) or not bool(_attacker.call("is_alive")) or not _line_clear(_attacker):
		_stop_attack()
		return
	if _attacker.global_position.distance_to(target.global_position) > profile.attack_range + 24.0:
		_stop_attack()
		return
	if _attack == Attack.WINDUP:
		_locked_aim = target.global_position + Vector2(0, 3)
		_attack = Attack.VOLLEY
	if _shots_in_turn < 3:
		var heading: Vector2 = _attacker.global_position.direction_to(_locked_aim)
		heading = heading.rotated(deg_to_rad(float(_shots_in_turn - 1) * 4.0))
		_attacker.call("shoot_recoil", heading)
		shot_requested.emit(_attacker, heading, self)
		shots_fired += 1
		_shots_in_turn += 1
		if attack_log.size() < 96: attack_log.append({"actor": _attacker.get_instance_id(), "shot": _shots_in_turn, "time": _time})
		_attack_left = profile.shot_interval
	else:
		_turn_cursor = (_turn_cursor + 1) % members.size()
		_stop_attack()


func _stop_attack() -> void:
	if is_instance_valid(_attacker):
		_attacker.set_meta(&"enemy_ai_is_attacking", false)
		_attacker.call("aim", _attacker.global_position.direction_to(target.global_position) if is_instance_valid(target) else Vector2.RIGHT, false)
	_attacker = null
	_attack = Attack.READY
	_attack_left = profile.turn_recovery if profile != null else 0.85
	_shots_in_turn = 0


func _on_member_died(member: Node2D) -> void:
	if member == _attacker: _stop_attack()
	members.erase(member)
	_routes.erase(member.get_instance_id())
	_repath_at.erase(member.get_instance_id())
	if members.is_empty():
		cleared.emit(self)
	elif state == State.ENGAGED:
		_turn_cursor %= members.size()
		_assign_slots()


func dismiss() -> void:
	_stop_attack()
	for member: CharacterBody2D in members.duplicate():
		if is_instance_valid(member): member.call("dismiss")
	members.clear()
	queue_free()
