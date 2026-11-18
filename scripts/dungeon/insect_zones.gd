extends Node2D
## Exploration packs favor paths and clearings outside authored horde arenas.
const PACK: Script = preload("res://scripts/enemies/insects/insect_pack.gd")
const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
const PALETTES: Script = preload("res://scripts/visual/insect_palettes.gd")
const COMPOSITIONS: Dictionary[int, Array] = {
	3: [["little", "little", "fly"], ["little", "fly", "fly"], ["little", "little", "little"], ["little", "little", "tall"], ["little", "fly", "tall"]],
	4: [["little", "little", "fly", "fly"], ["little", "little", "little", "fly"], ["little", "little", "fly", "tall"], ["little", "little", "fly", "tall"]],
	5: [["little", "little", "little", "fly", "fly"], ["little", "little", "little", "fly", "fly"], ["little", "little", "fly", "fly", "tall"], ["little", "little", "little", "fly", "tall"], ["little", "little", "fly", "fly", "tall"]],
	6: [["little", "little", "little", "little", "fly", "fly"], ["little", "little", "little", "little", "fly", "fly"], ["little", "little", "little", "fly", "fly", "tall"], ["little", "little", "little", "little", "fly", "tall"], ["little", "little", "little", "fly", "fly", "tall"]],
}
@export_enum("Monocromatico", "Cobre e gelo", "Casca clara") var palette_variant: int = 0
@export_range(3, 6, 1) var minimum_pack_size: int = 3
@export_range(3, 6, 1) var maximum_pack_size: int = 5
@export var maximum_alive: int = 12
@export var altar_clearance: float = 48.0
@export var acquisition_range: float = 192.0
@export var anchor_leash: float = 280.0
@export var minimum_anchor_distance: float = 320.0
@export var spawn_padding: float = 56.0
var player: Player = null
var gameplay: Node2D = null
var remains_system: Node2D = null
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
var altar_regions: Array[Dictionary] = []
var _path_cells: Dictionary[Vector2i, bool] = {}
var _clearing_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()


func configure(layers: Array, subject: Player, rules: Node2D, allowed: Dictionary,
		ground: Callable, height: Callable, encounters: Array, remains: Node2D = null) -> void:
	player = subject
	gameplay = rules
	remains_system = remains
	set_palette_variant(palette_variant)
	_allowed = allowed
	_floor_query = ground
	_height_query = height
	var clearing: CircleShape2D = CircleShape2D.new()
	clearing.radius = 34.0
	_clearing_query.shape = clearing
	_clearing_query.collision_mask = 1
	if random_seed == 0: _random.randomize()
	else: _random.seed = random_seed
	y_sort_enabled = true
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)): continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		if str(layer.get("__identifier", "")) in ["Floor_Paths", "Floor_StonePaths", "Floor_Bridges"]:
			var tiles: Array = (layer.get("gridTiles", []) as Array).duplicate()
			tiles.append_array(layer.get("autoLayerTiles", []) as Array)
			for tile: Dictionary in tiles:
				var point: Vector2 = offset + Vector2(float(tile.px[0]), float(tile.px[1]))
				_path_cells[Vector2i((point / 16.0).floor())] = true
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) not in ["FlyingEyeZone", "InsectZone"]: continue
			var config: Dictionary = ENTITIES.fields(entity)
			if not bool(config.get("Enabled", true)): continue
			var identifier: StringName = StringName(str(config.get("ZoneId", entity.iid)))
			var rect: Rect2 = ENTITIES.entity_rect(entity, offset)
			zones[identifier] = {"rect": Rect2(to_global(rect.position), rect.size), "config": config}
	for encounter: Node2D in encounters:
		if float(encounter.get("arena_radius")) > 0.0:
			altar_regions.append({"center": encounter.to_global(encounter.get("arena_center") as Vector2),
				"radius": float(encounter.get("arena_radius")) + altar_clearance})
		encounter.connect("started", _on_altar_started)
		encounter.connect("cleared", _on_altar_finished)
		encounter.connect("aborted", _on_altar_finished)
	set_physics_process(not zones.is_empty())


func set_palette_variant(value: int) -> void:
	palette_variant = posmod(value, PALETTES.PROPOSALS.size())
	for pack: Node2D in all_packs():
		pack.set("palette_variant", palette_variant)
		for actor: InsectActor in pack.get("members") as Array:
			actor.palette_variant = palette_variant
			actor.visual.call("set_palette_variant", palette_variant)
	if is_instance_valid(remains_system):
		remains_system.call("set_sprite_palette", PALETTES.remains_texture.bind(palette_variant))


func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build(): return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo: return
	if key.physical_keycode != KEY_F6 and key.keycode != KEY_F6: return
	set_palette_variant(palette_variant + 1)
	print("INSECT_PALETTE %d/3 %s" % [palette_variant + 1, PALETTES.LABELS[palette_variant]])
	get_viewport().set_input_as_handled()


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


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player): return
	_set_suspended(altar_active() or player.dead or player.intro_locked)
	if suspended: return
	_sense_left -= delta
	if _sense_left <= 0.0:
		_sense_left = 0.15
		var neighbors: Array[Node2D] = []
		for node: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
			if node is Node2D and node.has_method("is_alive") and bool(node.call("is_alive")): neighbors.append(node as Node2D)
		for pack: Node2D in all_packs(): pack.set("neighbors", neighbors)
	_update_zones(player.global_position)
	_spawn_left -= delta
	if _spawn_left <= 0.0:
		_spawn_left = 0.35
		_spawn_one_pack()


func _update_zones(point: Vector2) -> void:
	var selected: StringName = &""
	if zones.has(current_zone) and (zones[current_zone].rect as Rect2).grow(24.0).has_point(point):
		selected = current_zone
	else:
		for identifier: StringName in zones:
			if (zones[identifier].rect as Rect2).has_point(point):
				selected = identifier
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
		for identifier: StringName in zones:
			if active_zones.has(identifier): continue
			var distance: float = (zones[identifier].rect as Rect2).get_center().distance_squared_to(point)
			if distance < best:
				best = distance
				nearest = identifier
		_activate_zone(nearest)
		active_zones.erase(nearest)
		active_zones.push_front(nearest)


func _activate_zone(identifier: StringName) -> void:
	if identifier == &"" or runtime.has(identifier): return
	var rect: Rect2 = zones[identifier].rect as Rect2
	var candidates: Array[Vector2] = []
	var path_candidates: Array[Vector2] = []
	for cell: Vector2i in _allowed:
		var point: Vector2 = to_global(Vector2(cell * 16) + Vector2.ONE * 8.0)
		if not rect.grow(-32.0).has_point(point) or not outside_altars(point, 34.0) or not _is_clearing(point):
			continue
		candidates.append(point)
		if _near_path(cell):
			path_candidates.append(point)
	runtime[identifier] = {"packs": [], "spawned": 0, "candidates": candidates, "path_candidates": path_candidates}
	active_zones.append(identifier)


func outside_altars(point: Vector2, margin: float = 0.0) -> bool:
	for region: Dictionary in altar_regions:
		if point.distance_to(region.center as Vector2) < float(region.radius) + margin:
			return false
	return true


func supports_insects(point: Vector2) -> bool:
	return outside_altars(point, 8.2) and _floor_query.is_valid() and bool(_floor_query.call(point))


func _near_path(cell: Vector2i) -> bool:
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			if _path_cells.has(cell + Vector2i(x, y)):
				return true
	return false


func _is_clearing(point: Vector2) -> bool:
	for index: int in range(8):
		if not supports_insects(point + Vector2.from_angle(TAU * float(index) / 8.0) * 34.0):
			return false
	_clearing_query.transform = Transform2D(0.0, point)
	return get_world_2d().direct_space_state.intersect_shape(_clearing_query, 1).is_empty()


func _retire_zone(identifier: StringName) -> void:
	if not runtime.has(identifier): return
	for pack: Node2D in runtime[identifier].packs as Array:
		if is_instance_valid(pack): pack.call("dismiss")
	runtime.erase(identifier)
	active_zones.erase(identifier)
	evictions += 1


func viewport_bounds() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var viewport: Rect2 = get_viewport_rect()
	var result: Rect2 = Rect2(inverse * viewport.position, Vector2.ZERO)
	for corner: Vector2 in [viewport.end, Vector2(viewport.end.x, viewport.position.y), Vector2(viewport.position.x, viewport.end.y)]: result = result.expand(inverse * corner)
	return result


func choose_composition(count: int) -> Array[StringName]:
	var options: Array = COMPOSITIONS[clampi(count, 3, 6)]
	var chosen: Array = options[_random.randi_range(0, options.size() - 1)] as Array
	var result: Array[StringName] = []
	for kind: String in chosen: result.append(StringName(kind))
	for index: int in range(result.size() - 1, 0, -1):
		var other: int = _random.randi_range(0, index)
		var saved: StringName = result[index]
		result[index] = result[other]
		result[other] = saved
	return result


func _spawn_one_pack() -> void:
	if suspended or altar_active() or active_zones.is_empty() or live_count() > maximum_alive - 3: return
	for zone_attempt: int in range(active_zones.size()):
		_zone_cursor = (_zone_cursor + 1) % active_zones.size()
		var identifier: StringName = active_zones[_zone_cursor]
		var state: Dictionary = runtime[identifier]
		var config: Dictionary = zones[identifier].config as Dictionary
		if int(state.spawned) >= clampi(int(config.get("PackLimit", 2)), 0, 2): continue
		var candidates: Array[Vector2] = state.candidates as Array[Vector2]
		if candidates.is_empty(): continue
		var view: Rect2 = viewport_bounds()
		var count: int = _random.randi_range(clampi(minimum_pack_size, 3, 6), clampi(maximum_pack_size, minimum_pack_size, 6))
		count = mini(count, maximum_alive - live_count())
		var preferred: Array[Vector2] = state.path_candidates as Array[Vector2]
		for attempt: int in range(64):
			var choices: Array[Vector2] = preferred if not preferred.is_empty() and _random.randf() < 0.8 else candidates
			var anchor: Vector2 = choices[_random.randi_range(0, choices.size() - 1)]
			var acquisition: float = float(config.get("ActivationRangePx", acquisition_range))
			if anchor.distance_to(player.global_position) <= acquisition + 32.0: continue
			var minimum: float = float(config.get("MinimumPackDistancePx", minimum_anchor_distance))
			if not _spacing_ok(anchor, minimum): continue
			var starts: Array[Vector2] = []
			for member: int in range(count): starts.append(anchor + Vector2.from_angle(member * TAU / count) * 25.0)
			if not _safe_spawn(anchor, starts, view): continue
			var kinds: Array[StringName] = choose_composition(count)
			var pack: Node2D = PACK.new() as Node2D
			pack.name = "InsectPack_%s_%d" % [identifier, int(state.spawned)]
			pack.set("palette_variant", palette_variant)
			add_child(pack)
			pack.set_meta(&"minimum_anchor_distance", minimum)
			pack.tree_exiting.connect(_on_pack_exiting.bind(identifier, pack))
			pack.call("configure", anchor, starts, kinds, player, supports_insects, _height_query,
				float(config.get("AnchorRadiusPx", anchor_leash)), acquisition, _random.randf_range(0.0, TAU), remains_system)
			(state.packs as Array).append(pack)
			state.spawned = int(state.spawned) + 1
			spawn_total += 1
			if spawn_log.size() < 96: spawn_log.append({"zone": identifier, "anchor": anchor, "count": count, "composition": kinds, "viewport": view, "members": starts.duplicate()})
			return


func _spacing_ok(point: Vector2, requested: float) -> bool:
	for pack: Node2D in all_packs():
		if point.distance_to(pack.get("anchor") as Vector2) < maxf(requested, float(pack.get_meta(&"minimum_anchor_distance", minimum_anchor_distance))): return false
	return true


func _safe_spawn(anchor: Vector2, members: Array[Vector2], view: Rect2) -> bool:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 8.2 # Tall's enlarged 7.2px body plus a spawn clearance margin.
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 5
	var center_height: float = float(_height_query.call(anchor)) if _height_query.is_valid() else 0.0
	for point: Vector2 in members:
		if not supports_insects(point): return false
		query.transform = Transform2D(0.0, point)
		if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
		var height: float = float(_height_query.call(point)) if _height_query.is_valid() else 0.0
		if absf(height - center_height) > 4.0: return false
		if view.grow(spawn_padding).has_point(point - Vector2(0, height + 8.0)): return false
	return true


func all_packs() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for identifier: StringName in active_zones:
		if not runtime.has(identifier): continue
		for pack: Node2D in runtime[identifier].packs as Array:
			if is_instance_valid(pack) and not pack.is_queued_for_deletion(): result.append(pack)
	return result


func live_count() -> int:
	var result: int = 0
	for pack: Node2D in all_packs(): result += (pack.get("members") as Array).size()
	return result


func _on_pack_exiting(identifier: StringName, pack: Node2D) -> void:
	if runtime.has(identifier): (runtime[identifier].packs as Array).erase(pack)
