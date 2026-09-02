extends Node2D

const MINOTAUR_SCENE := preload("res://scenes/enemies/minotaur.tscn")
const SPIRIT_GHOST_SCENE := preload("res://scenes/enemies/spirit_ghost.tscn")
const SPIRIT_GHOST_ELITE_SCENE := preload(
	"res://scenes/enemies/elites/spirit_ghost_elite.tscn"
)

const INITIAL_MINOTAUR_COUNT := 3
const MINOTAUR_SPAWN_OFFSETS := [
	Vector2(-102.0, -58.0),
	Vector2(102.0, -58.0),
	Vector2(0.0, 108.0),
]
const GHOST_SPAWN_INTERVAL := 0.42
const GHOST_ELITE_DELAY := 10.0
const MAX_ACTIVE_GHOSTS := 42
const MIN_GHOST_SPEED := 38.0
const MAX_GHOST_SPEED := 50.0
const SPAWN_VISIBILITY_MARGIN := 20.0
const MAX_SPAWN_ATTEMPTS := 64
const GHOST_SEPARATION_RADIUS := 10.0
const EMPOWERED_GHOST_SEPARATION_RADIUS := 12.0
const ELITE_SEPARATION_RADIUS := 24.0

enum ShowcaseMode {
	MINOTAURS,
	SPIRIT_PROJECTION,
}

@onready var arena: Arena = get_parent().get_node("Arena")
@onready var target: Player = get_parent().get_node("Player")
@onready var camera: Camera2D = target.get_node("Camera2D")

var random := RandomNumberGenerator.new()
var mode := ShowcaseMode.MINOTAURS
var spirit_spawn_elapsed := 0.0
var spirit_projection_elapsed := 0.0
var spirit_elite_active := false


func _ready() -> void:
	random.randomize()
	call_deferred(&"_spawn_initial_minotaurs")


func _process(delta: float) -> void:
	if mode != ShowcaseMode.SPIRIT_PROJECTION:
		return

	spirit_projection_elapsed += delta
	if not spirit_elite_active and spirit_projection_elapsed >= GHOST_ELITE_DELAY:
		_spawn_spirit_elite()
		spirit_elite_active = true
		_empower_all_spirits()

	spirit_spawn_elapsed += delta
	while spirit_spawn_elapsed >= GHOST_SPAWN_INTERVAL:
		spirit_spawn_elapsed -= GHOST_SPAWN_INTERVAL
		if _active_ghost_count() < MAX_ACTIVE_GHOSTS:
			_spawn_spirit_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and (event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE)
	):
		toggle_showcase_mode()
		get_viewport().set_input_as_handled()


func toggle_showcase_mode() -> void:
	if mode == ShowcaseMode.MINOTAURS:
		start_spirit_projection()
	else:
		restore_minotaur_showcase()


func start_spirit_projection() -> void:
	mode = ShowcaseMode.SPIRIT_PROJECTION
	_clear_active_enemies()
	spirit_spawn_elapsed = 0.0
	spirit_projection_elapsed = 0.0
	spirit_elite_active = false
	_spawn_spirit_ghost()


func restore_minotaur_showcase() -> void:
	mode = ShowcaseMode.MINOTAURS
	_clear_active_enemies()
	spirit_spawn_elapsed = 0.0
	spirit_projection_elapsed = 0.0
	spirit_elite_active = false
	_spawn_initial_minotaurs()


func get_showcase_mode_name() -> StringName:
	return &"spirit_projection" if mode == ShowcaseMode.SPIRIT_PROJECTION else &"minotaurs"


func _clear_active_enemies() -> void:
	for child in get_children():
		child.queue_free()


func _spawn_initial_minotaurs() -> void:
	var safe_bounds := arena.get_player_bounds().grow(-16.0)
	for index in range(INITIAL_MINOTAUR_COUNT):
		var minotaur := MINOTAUR_SCENE.instantiate() as Node2D
		add_child(minotaur)
		minotaur.name = "Minotaur%d" % (index + 1)
		minotaur.global_position = (
			target.global_position + MINOTAUR_SPAWN_OFFSETS[index]
		).clamp(safe_bounds.position, safe_bounds.end)
		minotaur.call(&"setup", target, arena.get_player_bounds())


func _spawn_spirit_ghost() -> void:
	if _active_ghost_count() >= MAX_ACTIVE_GHOSTS:
		return

	var candidate_radius := (
		EMPOWERED_GHOST_SEPARATION_RADIUS
		if spirit_elite_active
		else GHOST_SEPARATION_RADIUS
	)
	var ghost := SPIRIT_GHOST_SCENE.instantiate() as Node2D
	add_child(ghost)
	ghost.global_position = _get_hidden_spawn_position(candidate_radius)
	ghost.call(
		&"setup",
		target,
		random.randf_range(MIN_GHOST_SPEED, MAX_GHOST_SPEED),
		spirit_elite_active
	)


func _spawn_spirit_elite() -> void:
	if not get_tree().get_nodes_in_group(&"spirit_ghost_elite").is_empty():
		return
	var elite := SPIRIT_GHOST_ELITE_SCENE.instantiate() as Node2D
	add_child(elite)
	elite.global_position = _get_hidden_spawn_position(ELITE_SEPARATION_RADIUS)
	elite.call(&"setup", target, arena.get_player_bounds())


func _empower_all_spirits() -> void:
	for ghost in get_tree().get_nodes_in_group(&"spirit_ghosts"):
		if is_instance_valid(ghost) and not ghost.is_queued_for_deletion():
			ghost.call(&"empower")


func _active_ghost_count() -> int:
	var count := 0
	for ghost in get_tree().get_nodes_in_group(&"spirit_ghosts"):
		if is_instance_valid(ghost) and not ghost.is_queued_for_deletion():
			count += 1
	return count


func _get_hidden_spawn_position(candidate_radius: float) -> Vector2:
	var bounds := arena.get_player_bounds().grow(-candidate_radius)
	var visibility_margin := maxf(SPAWN_VISIBILITY_MARGIN, candidate_radius + 1.0)
	var hidden_from_player := _get_visible_world_rect().grow(visibility_margin)
	var best_candidate := _farthest_hidden_corner(bounds, hidden_from_player)
	var best_clearance := _minimum_enemy_clearance(best_candidate, candidate_radius)

	for _attempt in range(MAX_SPAWN_ATTEMPTS):
		var candidate := Vector2(
			random.randf_range(bounds.position.x, bounds.end.x),
			random.randf_range(bounds.position.y, bounds.end.y)
		)
		if hidden_from_player.has_point(candidate):
			continue
		var clearance := _minimum_enemy_clearance(candidate, candidate_radius)
		if clearance >= 0.0:
			return candidate
		if clearance > best_clearance:
			best_candidate = candidate
			best_clearance = clearance
	return best_candidate


func _get_visible_world_rect() -> Rect2:
	var viewport_size := get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - viewport_size * 0.5, viewport_size)


func _minimum_enemy_clearance(candidate: Vector2, candidate_radius: float) -> float:
	var minimum_clearance := INF
	for child in get_children():
		if (
			not child is Node2D
			or not child.is_in_group(&"enemy_bodies")
			or child.is_queued_for_deletion()
		):
			continue
		var other_radius := GHOST_SEPARATION_RADIUS
		if child.has_method(&"get_separation_radius"):
			other_radius = float(child.call(&"get_separation_radius"))
		var center_distance := candidate.distance_to((child as Node2D).global_position)
		minimum_clearance = minf(
			minimum_clearance,
			center_distance - candidate_radius - other_radius
		)
	return minimum_clearance


func _farthest_hidden_corner(bounds: Rect2, visible_rect: Rect2) -> Vector2:
	var corners: Array[Vector2] = [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	]
	var best_corner := corners[0]
	var best_score := -INF
	for corner in corners:
		var hidden_bonus := 1000000.0 if not visible_rect.has_point(corner) else 0.0
		var score := hidden_bonus + corner.distance_squared_to(visible_rect.get_center())
		if score > best_score:
			best_score = score
			best_corner = corner
	return best_corner
