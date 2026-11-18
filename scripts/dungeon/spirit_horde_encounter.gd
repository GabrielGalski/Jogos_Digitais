extends Node2D
## Room-local encounter state and physics. There is deliberately no encounter UI.
signal started
signal cleared
signal stage_changed(stage: int)
signal progress_changed(defeated: int, target: int)
signal aborted

const GHOST: Script = preload("res://scripts/enemies/spirit_ghost.gd")
const HORDE_ENEMY: Script = preload("res://scripts/enemies/open_world_horde_enemy.gd")
const CENTIPEDE: Script = preload("res://scripts/enemies/flying_centipede.gd")
const BONE_BELL: Script = preload("res://scripts/enemies/bone_bell.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const HORDE_CATALOG: Script = preload("res://scripts/enemies/open_world_horde_catalog.gd")
const HORDE_SHOT: Script = preload("res://scripts/combat/projectiles/open_world_horde_shot.gd")
const PROFILE: Script = preload("res://scripts/enemies/spirit_horde_profile.gd")
const GROUND_NAVIGATION: Script = preload("res://scripts/enemies/ground_horde_navigation.gd")
const NAVIGATION: Script = preload("res://scripts/enemies/spirit_horde_navigation.gd")
const BUCKET: float = 24.0
const SPACING: float = 16.0
const NAVIGATION_BUDGET_USEC: int = 3500
const OPENING_SPAWNS_PER_TICK: int = 2
const MINIBOSS_MAX_WAIT: float = 8.0
const MINIBOSS_COVER_DISTANCE: float = 215.0
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
var _opening_remaining: int = 0
var _opening_delay: float = 0.0
var _miniboss_pending: bool = false
var _first_mob_at: float = -1.0
var _next_miniboss_check: float = 0.0
var _routing_remaining: float = 0.0
var _elapsed: float = 0.0
var _spawn_sequence: int = 0
var _mixed: bool = false
var _has_pedestal: bool = false
var miniboss: Node2D
var _walkable: Dictionary = {}
var completion_reason: StringName = &""
var ground_navigation: GROUND_NAVIGATION
var elapsed_seconds: float:
	get:
		return _elapsed
var _buckets: Dictionary = {}
var _waypoints: Dictionary = {}
var _route_deadlines: Dictionary = {}
var _previous_player: Vector2 = Vector2.ZERO
var projectiles: Array[Node2D] = []
var _projectiles_by_shooter: Dictionary[int, int] = {}


func configure(config: Dictionary, area: Rect2, subject: Player, rules: Node2D, query: Callable, remains: Node2D = null, height_query: Callable = Callable()) -> void:
	trigger_bounds = area
	player = subject
	gameplay = rules
	floor_query = query
	remains_system = remains
	encounter_id = str(config.get("EncounterId", "spirit_horde_1"))
	_mixed = HORDE_CATALOG.POOLS.has(encounter_id)
	_has_pedestal = bool(config.get("HasPedestal", false))
	if _mixed:
		_walkable = config.get("AllowedArenaCells", {}) as Dictionary
	activate_on_enter = bool(config.get("ActivateOnEnter", true))
	arena_radius = maxf(float(config.get("ArenaRadius", 0.0)), 0.0)
	arena_center = config.get("ArenaCenter", trigger_bounds.get_center()) as Vector2
	_height_query = height_query
	kill_target = int(profile.get("open_world_kill_limit")) if _mixed else maxi(int(config.get("KillTarget", 40)), 1)
	clear_condition = str(config.get("ClearCondition", clear_condition))
	entry_condition = str(config.get("EntryCondition", entry_condition))
	_random.randomize()
	if arena_radius <= 0.0:
		navigation.call("configure", trigger_bounds.grow(1024.0), _walkable)
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
	if _mixed:
		_init_ground_navigation()
	if arena_boundary != null:
		if not _mixed:
			navigation.call("configure", trigger_bounds.grow(1024.0), _walkable)
		gameplay.set_meta(&"active_pedestal_encounter", self)
		arena_boundary.call("set_active", true)
	gameplay.call("set_condition", entry_condition, false)
	var chance: float = float(profile.get("miniboss_spawn_chance"))
	_miniboss_pending = _has_pedestal and chance > 0.0 and (chance >= 1.0 or _random.randf() < chance)
	_opening_remaining = int(profile.get("open_world_initial_pack" if _mixed else "initial_pack"))
	_opening_delay = _spawn_interval()
	_spawn_remaining = _spawn_interval()
	started.emit()


func _init_ground_navigation() -> void:
	if ground_navigation != null:
		return
	ground_navigation = GROUND_NAVIGATION.new()
	ground_navigation.configure(trigger_bounds.grow(320.0), self, floor_query)
	navigation = ground_navigation


func needs_navigation_warmup() -> bool:
	return _mixed and phase == Phase.WAITING and (ground_navigation == null or not ground_navigation.sampling_done)


func warmup_navigation(deadline_usec: int) -> void:
	_init_ground_navigation()
	ground_navigation.sample_cells(deadline_usec)


func _spawn_interval() -> float:
	return float(profile.get("open_world_spawn_interval" if _mixed else "spawn_interval"))


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
	_opening_delay = maxf(0.0, _opening_delay - delta)
	_routing_remaining -= delta
	var refresh_routes: bool = _routing_remaining <= 0.0
	if _mixed:
		var deadline: int = Time.get_ticks_usec() + NAVIGATION_BUDGET_USEC
		ground_navigation.sample_cells(deadline)
		if ground_navigation.distances.is_empty() or ground_navigation.flow_building or refresh_routes:
			ground_navigation.update_target(subject, deadline)
		if ground_navigation.distances.is_empty():
			_previous_player = subject
			return
	if _opening_delay > 0.0:
		_previous_player = subject
		return
	_elapsed += delta
	if _check_completion():
		return
	if _mixed:
		_update_stage()
	var boss_arrived: bool = _miniboss_pending and _try_miniboss_entry()
	if not boss_arrived and completion_reason.is_empty():
		if _opening_remaining > 0:
			var batch: int = mini(_opening_remaining, OPENING_SPAWNS_PER_TICK)
			for index: int in range(batch):
				_spawn_one()
			_opening_remaining -= batch
		else:
			_spawn_remaining -= delta
		if _spawn_remaining <= 0.0:
			_spawn_remaining += _spawn_interval()
			var reinforcements: int = int(profile.get("open_world_reinforcements")) if _mixed else 2 + difficulty_stage
			for index: int in range(reinforcements):
				_spawn_one()
	if refresh_routes:
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


func _try_miniboss_entry() -> bool:
	var delay: float = float(profile.get("miniboss_entry_delay"))
	var waited: float = _elapsed - maxf(_first_mob_at, 0.0)
	var force_entry: bool = not completion_reason.is_empty() or waited >= maxf(MINIBOSS_MAX_WAIT, delay)
	if not force_entry and (_first_mob_at < 0.0 or waited < delay or _elapsed < _next_miniboss_check):
		return false
	_next_miniboss_check = _elapsed + 0.2
	var subject: Vector2 = to_local(player.surface_world_position()) - Vector2(0, 5)
	var visible_area: Rect2 = viewport_bounds().grow(-6.0)
	var groups: Array[Vector2] = []
	var counts: Array[int] = []
	groups.resize(8)
	counts.resize(8)
	groups.fill(Vector2.ZERO)
	counts.fill(0)
	var best: int = 0
	var in_view: int = 0
	for actor: Node2D in actors:
		var point: Vector2 = to_local(CONTACTS.damage_center(actor))
		var offset: Vector2 = point - subject
		var distance_squared: float = offset.length_squared()
		if distance_squared < 24.0 * 24.0:
			continue
		var approaching: bool = visible_area.has_point(point) and distance_squared <= MINIBOSS_COVER_DISTANCE * MINIBOSS_COVER_DISTANCE
		if approaching:
			in_view += 1
		elif not force_entry or distance_squared > 320.0 * 320.0:
			continue
		var sector: int = posmod(roundi(offset.angle() / (TAU / 8.0)), 8)
		groups[sector] += offset.normalized()
		counts[sector] += 1
		if counts[sector] > counts[best]:
			best = sector
	if in_view < 2 and not force_entry:
		return false
	var outside: Vector2 = groups[best].normalized() if counts[best] > 0 else Vector2.from_angle(_random.randf_range(-PI, PI))
	_spawn_miniboss(subject, outside)
	return true


func _spawn_miniboss(subject: Vector2, outside: Vector2) -> void:
	_miniboss_pending = false
	var view: Rect2 = viewport_bounds().grow(18.0)
	var border_x: float = view.end.x if outside.x > 0.0 else view.position.x
	var border_y: float = view.end.y if outside.y > 0.0 else view.position.y
	var distance_x: float = (border_x - subject.x) / outside.x if absf(outside.x) > 0.001 else INF
	var distance_y: float = (border_y - subject.y) / outside.y if absf(outside.y) > 0.001 else INF
	var distance: float = maxf(145.0, minf(distance_x, distance_y))
	if int(profile.get("miniboss_kind")) == PROFILE.MinibossKind.CENTIPEDE:
		var centipede: CENTIPEDE = CENTIPEDE.new()
		centipede.name = "FlyingCentipede"
		centipede.player = player
		centipede.horde_members = actors
		centipede.entry_heading = -outside
		centipede.entry_distance = distance
		centipede.arena_origin = to_global(arena_center)
		miniboss = centipede
	else:
		var bell: BONE_BELL = BONE_BELL.new()
		bell.name = "BoneBell"
		bell.player = player
		bell.position = subject + outside * distance
		miniboss = bell
	miniboss.connect(&"defeated", _on_miniboss_defeated)
	add_child(miniboss)


func _on_miniboss_defeated() -> void:
	miniboss = null
	_check_completion()


func viewport_bounds() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var view: Rect2 = get_viewport_rect()
	var area: Rect2 = Rect2(to_local(inverse * view.position), Vector2.ZERO)
	for corner: Vector2 in [view.end, Vector2(view.end.x, view.position.y), Vector2(view.position.x, view.end.y)]:
		area = area.expand(to_local(inverse * corner))
	return area


func _spawn_one() -> Node2D:
	var limit: int = int(profile.get("open_world_maximum_alive" if _mixed else "maximum_alive"))
	if phase != Phase.ACTIVE or actors.size() >= limit:
		return null
	var view: Rect2 = viewport_bounds()
	var outer: Rect2 = trigger_bounds.merge(view).grow(float(profile.get("spawn_margin")))
	var side: int = _spawn_sequence % 4
	_spawn_sequence += 1
	if arena_radius > 0.0:
		if _mixed:
			# A riverbank can close an entire approach. Try the other sectors.
			for offset: int in range(4):
				var recruit: Node2D = _spawn_arena_spirit(view, (side + offset) % 4)
				if recruit != null:
					return recruit
			return null
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
		if _mixed:
			point = ground_navigation.center(ground_navigation.cell(point))
		if view.grow(20.0).has_point(point):
			continue
		var occupied: bool = false
		for other: Node2D in actors:
			var spacing: float = 32.0 if _mixed else SPACING
			if other.position.distance_squared_to(point) < spacing * spacing:
				occupied = true
				break
		if not occupied and (not _mixed or bool(navigation.call("can_enter", point, center))):
			return _create_spirit(point, view, side)
	return null


func _create_spirit(point: Vector2, view: Rect2, side: int) -> Node2D:
	var ghost: Node2D
	if _mixed:
		var fighter: HORDE_ENEMY = HORDE_ENEMY.new()
		fighter.configure(HORDE_CATALOG.pick(encounter_id, _elapsed, _random), player, _height_query)
		ghost = fighter
	else:
		ghost = GHOST.new() as Node2D
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
	if _first_mob_at < 0.0:
		_first_mob_at = _elapsed
	ghost.connect("died", _on_killed)
	ghost.connect("consumed", _on_consumed)
	_route_deadlines[ghost.get_instance_id()] = _elapsed + _random.randf_range(0.0, 0.3)
	return ghost


func spawn_horde_projectile(shot: Node2D) -> void:
	var shooter: Node2D = shot.get("shooter") as Node2D
	var id: int = shooter.get_instance_id()
	if phase != Phase.ACTIVE or projectiles.size() >= int(profile.get("open_world_maximum_projectiles")) \
			or int(_projectiles_by_shooter.get(id, 0)) >= int(profile.get("open_world_projectiles_per_enemy")):
		shot.free()
		return
	projectiles.append(shot)
	_projectiles_by_shooter[id] = int(_projectiles_by_shooter.get(id, 0)) + 1
	shot.tree_exiting.connect(_on_projectile_exiting.bind(shot, id), CONNECT_ONE_SHOT)
	add_child(shot)


func _on_projectile_exiting(shot: Node2D, shooter_id: int) -> void:
	projectiles.erase(shot)
	var remaining: int = int(_projectiles_by_shooter.get(shooter_id, 1)) - 1
	if remaining <= 0:
		_projectiles_by_shooter.erase(shooter_id)
	else:
		_projectiles_by_shooter[shooter_id] = remaining


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
				var clearance: float = float(actor.call("get_separation_radius")) + float(other.call("get_separation_radius")) if _mixed else BUCKET
				if distance < 0.001:
					away = Vector2.RIGHT.rotated(float(mini(actor.get_instance_id(), other.get_instance_id()) % 628) * 0.01)
					away *= 1.0 if actor.get_instance_id() > other.get_instance_id() else -1.0
					distance = 0.01
				if distance < clearance:
					correction += away.normalized() * (1.0 - distance / clearance)
	return correction.limit_length(1.6)


func _move_actor(actor: CharacterBody2D, subject: Vector2, delta: float) -> void:
	if actor.has_meta(&"card_control"):
		return
	var identifier: int = actor.get_instance_id()
	if _mixed or _elapsed >= float(_route_deadlines.get(identifier, 0.0)) or not _waypoints.has(identifier):
		_waypoints[identifier] = navigation.call("waypoint", actor.position, subject)
		_route_deadlines[identifier] = _elapsed + 0.32
	var waypoint: Vector2 = _waypoints[identifier] as Vector2
	if not _mixed and (actor.position.distance_squared_to(subject) < 72.0 * 72.0 or actor.position.distance_squared_to(waypoint) < 16.0 * 16.0):
		waypoint = subject
	var forward: Vector2 = actor.position.direction_to(waypoint)
	var distance: float = actor.position.distance_to(subject)
	var sway: float = float(actor.get("sway_strength"))
	var oscillation: float = sin(_elapsed * (2.0 + difficulty_stage * 0.65) + float(actor.get("phase")))
	var bend: float = sway * oscillation * clampf(distance / 80.0, 0.0, 1.0)
	var direction: Vector2 = (forward + forward.orthogonal() * bend).normalized()
	if actor is HORDE_ENEMY:
		direction = (actor as HORDE_ENEMY).combat_direction(direction, distance, delta)
	var speed: float = float(actor.get("movement_speed"))
	var impulse: Vector2 = actor.get("hit_velocity") as Vector2
	actor.set("hit_velocity", impulse * exp(-12.0 * delta))
	var steering: Vector2 = (direction + _separation(actor) * (2.0 if _mixed else 1.35)).limit_length(1.0)
	if _mixed:
		steering = ground_navigation.steer(actor.position, steering)
	actor.velocity = steering * speed + impulse
	var previous: Vector2 = actor.position
	actor.move_and_slide()
	if _mixed:
		_resolve_crowd_contacts(actor)
	if _mixed and not ground_navigation.has_floor(actor.position):
		actor.position = previous
	if actor is HORDE_ENEMY:
		(actor as HORDE_ENEMY).sync_floor_height()
		return
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
	player.receive_contact_damage(int(actor.get("contact_damage")), actor.global_position.direction_to(player.global_position), 35.0, actor)
	if player.health < health_before and not player.dead:
		player.apply_contact_slow(float(profile.get("contact_slow_factor")), float(profile.get("contact_slow_duration")), float(profile.get("post_slow_invulnerability")))
	actor.call("consume_on_contact")


func _resolve_crowd_contacts(actor: Node2D) -> void:
	# Relax penetrating pairs locally without forcing either body into scenery.
	var bucket: Vector2i = Vector2i((actor.position / BUCKET).floor())
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			for other: Node2D in _buckets.get(bucket + Vector2i(x, y), []):
				if other.get_instance_id() <= actor.get_instance_id() or not bool(other.call("is_alive")):
					continue
				var away: Vector2 = actor.position - other.position
				var distance: float = away.length()
				if distance >= 15.0:
					continue
				var normal: Vector2 = away / distance if distance > 0.001 else Vector2.RIGHT.rotated(float(actor.get_instance_id() % 628) * 0.01)
				var correction: Vector2 = normal * (15.0 - distance) * 0.5
				if ground_navigation.can_move(actor.position, correction):
					actor.position += correction
				if ground_navigation.can_move(other.position, -correction):
					other.position -= correction


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
	if _check_completion():
		return
	_update_stage()


func _update_stage() -> void:
	var progress: float = float(defeated_count) / float(kill_target) if _mixed else float(defeated_count) / 40.0
	if _mixed:
		progress = maxf(progress, _elapsed / float(profile.get("open_world_time_limit")))
	var next_stage: int = mini(int(progress * 4.0), 3)
	if next_stage != difficulty_stage:
		difficulty_stage = next_stage
		for survivor: Node2D in actors:
			survivor.call("apply_profile", profile, difficulty_stage)
		stage_changed.emit(difficulty_stage)


func _check_completion() -> bool:
	# Independent completion rules allow future experimental criteria here.
	if phase != Phase.ACTIVE:
		return false
	if completion_reason.is_empty():
		if defeated_count >= kill_target:
			completion_reason = &"kills"
		elif _mixed and _elapsed >= float(profile.get("open_world_time_limit")):
			completion_reason = &"time"
	if completion_reason.is_empty() or _miniboss_pending or is_instance_valid(miniboss):
		return false
	_complete()
	return true


func completion_progress() -> float:
	if phase == Phase.CLEARED:
		return 1.0
	var result: float = float(defeated_count) / maxf(float(kill_target), 1.0)
	if _mixed:
		result = maxf(result, _elapsed / maxf(float(profile.get("open_world_time_limit")), 0.001))
	return clampf(result, 0.0, 1.0)


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
	_miniboss_pending = false
	if is_instance_valid(miniboss):
		miniboss.call(&"dismiss")
		miniboss = null
	if _mixed:
		for child: Node in get_children():
			if child is HORDE_SHOT:
				(child as HORDE_SHOT).dismiss()
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
