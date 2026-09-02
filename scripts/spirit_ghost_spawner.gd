extends Node2D

const SPIRIT_GHOST_SCENE := preload("res://scenes/enemies/spirit_ghost.tscn")
const MIMIC_SCENE := preload("res://scenes/enemies/elites/mimic.tscn")
const INITIAL_SPAWN_COUNT := 12
const RECURRING_SPAWN_INTERVAL := 0.42
const MAX_ACTIVE_GHOSTS := 42
const MIN_GHOST_SPEED := 38.0
const MAX_GHOST_SPEED := 50.0
const SPAWN_VISIBILITY_MARGIN := 20.0
const MAX_SPAWN_ATTEMPTS := 64
const GHOST_SEPARATION_RADIUS := 10.0
const MIMIC_SEPARATION_RADIUS := 25.0

@onready var arena: Arena = get_parent().get_node("Arena")
@onready var target: Player = get_parent().get_node("Player")
@onready var camera: Camera2D = target.get_node("Camera2D")

var random := RandomNumberGenerator.new()
var spawn_elapsed := 0.0


func _ready() -> void:
	random.randomize()
	call_deferred(&"_spawn_initial_wave")


func _process(delta: float) -> void:
	spawn_elapsed += delta
	if spawn_elapsed < RECURRING_SPAWN_INTERVAL:
		return

	spawn_elapsed = fmod(spawn_elapsed, RECURRING_SPAWN_INTERVAL)
	if _active_ghost_count() < MAX_ACTIVE_GHOSTS:
		_spawn_ghost()


func _spawn_initial_wave() -> void:
	_spawn_mimic()
	for _index in range(INITIAL_SPAWN_COUNT):
		_spawn_ghost()


func _spawn_ghost() -> void:
	if _active_ghost_count() >= MAX_ACTIVE_GHOSTS:
		return

	var spawn_position := _get_hidden_spawn_position(GHOST_SEPARATION_RADIUS)
	var ghost := SPIRIT_GHOST_SCENE.instantiate() as SpiritGhost
	add_child(ghost)
	ghost.global_position = spawn_position
	ghost.setup(target, random.randf_range(MIN_GHOST_SPEED, MAX_GHOST_SPEED))


func _spawn_mimic() -> void:
	if not get_tree().get_nodes_in_group(&"mimic_elite").is_empty():
		return
	var spawn_position := _get_hidden_spawn_position(MIMIC_SEPARATION_RADIUS)
	var mimic := MIMIC_SCENE.instantiate()
	add_child(mimic)
	mimic.global_position = spawn_position
	mimic.call(&"setup", target, arena.get_player_bounds())


func _get_hidden_spawn_position(candidate_radius: float = GHOST_SEPARATION_RADIUS) -> Vector2:
	var bounds := arena.get_player_bounds().grow(6.0)
	var visibility_margin := maxf(SPAWN_VISIBILITY_MARGIN, candidate_radius + 1.0)
	var hidden_from_player := _get_visible_world_rect().grow(visibility_margin)
	var best_candidate := _farthest_hidden_corner(bounds, hidden_from_player)
	var best_clearance := _minimum_enemy_clearance(best_candidate, candidate_radius)

	# Amostragem uniforme permite qualquer ponto da arena que esteja fora da camera.
	# Entre candidatos validos, a distancia minima evita corpos sobrepostos no spawn.
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


func _active_ghost_count() -> int:
	var count := 0
	for ghost in get_tree().get_nodes_in_group(&"spirit_ghosts"):
		if is_instance_valid(ghost) and not ghost.is_queued_for_deletion():
			count += 1
	return count


func _farthest_hidden_corner(bounds: Rect2, visible_rect: Rect2) -> Vector2:
	var corners: Array[Vector2] = [
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y)
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
