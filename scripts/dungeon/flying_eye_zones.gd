extends Node2D
## Two recent exploration zones, at most two packs each. No HUD or spawn markers.

const PACK: Script = preload("res://scripts/enemies/flying_eye_pack.gd")
const ORB: Script = preload("res://scripts/combat/projectiles/flying_eye_orb.gd")
const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
var profile: FlyingEyeProfile = FlyingEyeProfile.new()
var player: Player = null
var gameplay: Node2D = null
var zones: Dictionary[StringName, Dictionary] = {}
var active_zones: Array[StringName] = []
var runtime: Dictionary[StringName, Dictionary] = {}
var current_zone: StringName = &""
var spawn_total: int = 0
var evictions: int = 0
var spawn_log: Array[Dictionary] = []
var suspended: bool = false
var random_seed: int = 0
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _allowed: Dictionary = {}
var _floor_query: Callable = Callable()
var _height_query: Callable = Callable()
var _spawn_left: float = 0.0
var _sense_left: float = 0.0
var _zone_cursor: int = 0
var _orb_root: Node2D = null


func configure(layers: Array, subject: Player, rules: Node2D, allowed: Dictionary,
		ground: Callable, height: Callable, encounters: Array) -> void:
	player = subject
	gameplay = rules
	_allowed = allowed
	_floor_query = ground
	_height_query = height
	if random_seed == 0: _random.randomize()
	else: _random.seed = random_seed
	y_sort_enabled = true
	_orb_root = Node2D.new()
	_orb_root.name = "Projectiles"
	add_child(_orb_root)
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)): continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "FlyingEyeZone": continue
			var config: Dictionary = ENTITIES.fields(entity)
			if not bool(config.get("Enabled", true)): continue
			var id: StringName = StringName(str(config.get("ZoneId", entity.iid)))
			var rect: Rect2 = ENTITIES.entity_rect(entity, offset)
			zones[id] = {"rect": Rect2(to_global(rect.position), rect.size), "config": config}
	for encounter: Node2D in encounters:
		encounter.connect("started", _on_altar_started)
		encounter.connect("cleared", _on_altar_finished)
		encounter.connect("aborted", _on_altar_finished)
	set_physics_process(not zones.is_empty())


func altar_active() -> bool:
	if not is_instance_valid(gameplay) or not gameplay.has_meta(&"active_pedestal_encounter"): return false
	var encounter: Node = gameplay.get_meta(&"active_pedestal_encounter") as Node
	return is_instance_valid(encounter) and int(encounter.get("phase")) == 1


func _on_altar_started() -> void:
	_set_suspended(true)


func _on_altar_finished() -> void:
	_set_suspended(altar_active())


func _set_suspended(value: bool) -> void:
	if suspended == value: return
	suspended = value
	for pack: Node2D in all_packs(): pack.call("set_suspended", value)
	if value:
		for orb: Node in _orb_root.get_children(): orb.call("dismiss")


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player): return
	_set_suspended(altar_active() or player.dead or player.intro_locked)
	_sense_left -= delta
	if _sense_left <= 0.0:
		_sense_left = 0.15
		var neighbors: Array[Node2D] = []
		for node: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
			if node is Node2D and node.has_method("is_alive") and bool(node.call("is_alive")): neighbors.append(node as Node2D)
		for pack: Node2D in all_packs(): pack.set("neighbors", neighbors)
	if suspended: return
	_update_zones(player.global_position)
	_spawn_left -= delta
	if _spawn_left <= 0.0:
		_spawn_left = profile.spawn_interval
		_spawn_one_pack()


func _update_zones(point: Vector2) -> void:
	var selected: StringName = &""
	if zones.has(current_zone) and (zones[current_zone].rect as Rect2).grow(24.0).has_point(point):
		selected = current_zone
	else:
		for id: StringName in zones:
			if (zones[id].rect as Rect2).has_point(point):
				selected = id
				break
	if selected == &"": return
	if selected != current_zone:
		if not active_zones.has(selected):
			if active_zones.size() >= 2: _retire_zone(active_zones[0])
			_activate_zone(selected)
		else:
			active_zones.erase(selected)
			active_zones.append(selected)
		current_zone = selected
	if active_zones.size() == 1 and zones.size() > 1:
		var nearest: StringName = &""
		var best: float = INF
		for id: StringName in zones:
			if active_zones.has(id): continue
			var distance: float = (zones[id].rect as Rect2).get_center().distance_squared_to(point)
			if distance < best:
				best = distance
				nearest = id
		_activate_zone(nearest)
		# Preloaded/unvisited neighbor is older than the current visited zone.
		active_zones.erase(nearest)
		active_zones.push_front(nearest)


func _activate_zone(id: StringName) -> void:
	if id == &"" or runtime.has(id): return
	var rect: Rect2 = zones[id].rect as Rect2
	var candidates: Array[Vector2] = []
	for cell: Vector2i in _allowed:
		var point: Vector2 = to_global(Vector2(cell * 16) + Vector2.ONE * 8.0)
		if rect.grow(-32.0).has_point(point): candidates.append(point)
	runtime[id] = {"packs": [], "spawned": 0, "candidates": candidates}
	active_zones.append(id)


func _retire_zone(id: StringName) -> void:
	if not runtime.has(id): return
	for pack: Node2D in runtime[id].packs as Array:
		if not is_instance_valid(pack): continue
		_clear_pack_orbs(pack.get_instance_id())
		pack.call("dismiss")
	runtime.erase(id)
	active_zones.erase(id)
	evictions += 1


func viewport_bounds() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var viewport: Rect2 = get_viewport_rect()
	var result: Rect2 = Rect2(inverse * viewport.position, Vector2.ZERO)
	for corner: Vector2 in [viewport.end, Vector2(viewport.end.x, viewport.position.y), Vector2(viewport.position.x, viewport.end.y)]: result = result.expand(inverse * corner)
	return result


func _spawn_one_pack() -> void:
	if suspended or altar_active() or active_zones.is_empty(): return
	for attempt_zone: int in range(active_zones.size()):
		_zone_cursor = (_zone_cursor + 1) % active_zones.size()
		var id: StringName = active_zones[_zone_cursor]
		var state: Dictionary = runtime[id]
		var config: Dictionary = zones[id].config as Dictionary
		var limit: int = clampi(int(config.get("PackLimit", profile.maximum_packs_per_zone)), 0, 2)
		if int(state.spawned) >= limit: continue
		var candidates: Array[Vector2] = state.candidates as Array[Vector2]
		if candidates.is_empty(): continue
		var view: Rect2 = viewport_bounds()
		var minimum: int = clampi(profile.minimum_pack_size, 2, 5)
		var count: int = _random.randi_range(minimum, clampi(profile.maximum_pack_size, minimum, 5))
		for attempt: int in range(profile.spawn_attempts):
			var anchor: Vector2 = candidates[_random.randi_range(0, candidates.size() - 1)]
			var acquisition: float = float(config.get("ActivationRangePx", profile.acquisition_range))
			if anchor.distance_to(player.global_position) <= acquisition + 32.0: continue
			if not _anchor_spacing_ok(anchor, float(config.get("MinimumPackDistancePx", profile.minimum_anchor_distance))): continue
			var starts: Array[Vector2] = []
			for member: int in range(count): starts.append(anchor + Vector2.from_angle(member * TAU / count) * 20.0)
			if not _safe_spawn(anchor, starts, view): continue
			var pack: Node2D = PACK.new() as Node2D
			pack.name = "Pack_%s_%d" % [id, int(state.spawned)]
			add_child(pack)
			pack.connect("shot_requested", _on_shot_requested)
			pack.tree_exiting.connect(_on_pack_exiting.bind(id, pack))
			pack.set_meta(&"minimum_anchor_distance", float(config.get("MinimumPackDistancePx", profile.minimum_anchor_distance)))
			pack.call("configure", anchor, starts, player, profile, _floor_query, _height_query,
				float(config.get("AnchorRadiusPx", profile.anchor_leash)), acquisition, _random.randf_range(0.0, TAU))
			(state.packs as Array).append(pack)
			state.spawned = int(state.spawned) + 1
			spawn_total += 1
			if spawn_log.size() < 96: spawn_log.append({"zone": id, "anchor": anchor, "count": count, "viewport": view, "members": starts.duplicate()})
			return


func _anchor_spacing_ok(point: Vector2, requested: float) -> bool:
	for pack: Node2D in all_packs():
		if point.distance_to(pack.get("anchor") as Vector2) < maxf(requested, float(pack.get_meta(&"minimum_anchor_distance", profile.minimum_anchor_distance))): return false
	return true


func _safe_spawn(anchor: Vector2, members: Array[Vector2], view: Rect2) -> bool:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = profile.body_radius + 24.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, anchor)
	query.collision_mask = 1
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	for point: Vector2 in members:
		if not _floor_query.is_valid() or not bool(_floor_query.call(point)): return false
		var height: float = float(_height_query.call(point)) if _height_query.is_valid() else 0.0
		var rendered_point: Vector2 = point - Vector2(0, height + 8.0)
		if view.grow(profile.spawn_padding + 8.0).has_point(rendered_point): return false
	return true


func all_packs() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for id: StringName in active_zones:
		if not runtime.has(id): continue
		for pack: Node2D in runtime[id].packs as Array:
			if is_instance_valid(pack) and not pack.is_queued_for_deletion(): result.append(pack)
	return result


func live_count() -> int:
	var result: int = 0
	for pack: Node2D in all_packs(): result += (pack.get("members") as Array).size()
	return result


func _on_shot_requested(actor: Node2D, heading: Vector2, pack: Node2D) -> void:
	if suspended or altar_active() or not is_instance_valid(actor): return
	var orb: Node2D = ORB.new() as Node2D
	orb.set("target", player)
	orb.set("shooter", actor)
	orb.set("direction", heading)
	orb.set("pack_id", pack.get_instance_id())
	orb.set("damage", profile.orb_damage)
	orb.set("speed", profile.orb_speed)
	orb.set("radius", profile.orb_radius)
	orb.set("remaining", profile.orb_lifetime)
	orb.set("height_query", _height_query)
	orb.set("_visual_height", actor.get("floor_height"))
	_orb_root.add_child(orb)
	orb.global_position = actor.global_position + heading * 10.0
	orb.reset_physics_interpolation()


func _clear_pack_orbs(identifier: int) -> void:
	for orb: Node in _orb_root.get_children():
		if int(orb.get("pack_id")) == identifier: orb.call("dismiss")


func _on_pack_exiting(id: StringName, pack: Node2D) -> void:
	if runtime.has(id): (runtime[id].packs as Array).erase(pack)
