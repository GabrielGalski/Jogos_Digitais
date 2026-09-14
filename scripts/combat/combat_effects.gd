extends Node2D
class_name CombatEffects

const ELECTRIC_ARC_SCENE := preload("res://scenes/combat/effects/electric_arc.tscn")
const ELECTRIC_EXPLOSION_SCENE := preload(
	"res://scenes/combat/effects/electric_explosion.tscn"
)
const DEFAULT_RANDOM_SEED := 2667
const CHAIN_RANGE := 84.0
const MAX_CHAIN_JUMPS := 6
const CHAIN_STEP_DELAY := 0.04

var random := RandomNumberGenerator.new()
var chain_generation := 0
var impact_camera: Camera2D
var camera_impulse := 0.0
var feedback_time := 0.0
var feedback_offset: Vector2 = Vector2.ZERO
var camera_feedback_enabled: bool = true


func _process(delta: float) -> void:
	if not is_instance_valid(impact_camera):
		impact_camera = get_viewport().get_camera_2d()
	if not is_instance_valid(impact_camera):
		return
	impact_camera.offset -= feedback_offset
	feedback_offset = Vector2.ZERO
	if not camera_feedback_enabled:
		camera_impulse = 0.0
		return
	feedback_time += delta
	camera_impulse = move_toward(camera_impulse, 0.0, delta * 12.0)
	# Deslocamento pequeno em pixels lógicos; não altera tempo nem posição do jogador.
	feedback_offset = Vector2(sin(feedback_time * 91.0), cos(feedback_time * 113.0)) * camera_impulse
	impact_camera.offset += feedback_offset


func _exit_tree() -> void:
	if is_instance_valid(impact_camera):
		impact_camera.offset -= feedback_offset
		feedback_offset = Vector2.ZERO


func apply_hit(enemy: Node2D, damage: float, direction: Vector2, impulse: float) -> void:
	if damage <= 0.0 or not _is_valid_enemy(enemy):
		return
	if enemy.has_method(&"receive_impact"):
		enemy.call(&"receive_impact", direction, impulse)
	enemy.call(&"take_damage", damage)


func _ready() -> void:
	reset_random_seed()


func reset_random_seed(seed_value: int = DEFAULT_RANDOM_SEED) -> void:
	camera_impulse = 0.0
	feedback_time = 0.0
	if is_instance_valid(impact_camera):
		impact_camera.offset -= feedback_offset
		feedback_offset = Vector2.ZERO
	chain_generation += 1
	random.seed = seed_value


func trigger_primary_modifiers(
	primary_target: Node2D,
	hit_position: Vector2,
	chain_damage: float,
	explosion_radius: float,
	explosion_damage: float
) -> void:
	trigger_electric_chain(primary_target, hit_position, chain_damage)
	trigger_explosion(hit_position, explosion_radius, explosion_damage)


func trigger_electric_chain(
	primary_target: Node2D,
	hit_position: Vector2,
	chain_damage: float,
	additional_excluded_ids: Array[int] = []
) -> void:
	if chain_damage <= 0.0:
		return
	var excluded_ids: Array[int] = additional_excluded_ids.duplicate()
	if is_instance_valid(primary_target):
		excluded_ids.append(primary_target.get_instance_id())
	_run_electric_chain(hit_position, excluded_ids, chain_damage)


func trigger_explosion(
	center: Vector2,
	radius: float,
	damage: float
) -> void:
	_spawn_explosion_visual(center, radius)
	camera_impulse = maxf(camera_impulse, clampf(radius / 24.0, 0.4, 1.2))
	var hit_ids: Dictionary = {}
	for enemy_node in get_tree().get_nodes_in_group(&"minotaurs"):
		if not _is_valid_enemy(enemy_node):
			continue
		var enemy := enemy_node as Node2D
		var enemy_id := enemy.get_instance_id()
		if hit_ids.has(enemy_id) or enemy.global_position.distance_to(center) > radius:
			continue
		hit_ids[enemy_id] = true
		var outward := (enemy.global_position - center).normalized()
		# O alvo central preserva a direção do acerto principal.
		if outward.is_zero_approx():
			outward = enemy.get(&"last_hit_direction")
		var falloff := 1.0 - 0.45 * clampf(enemy.global_position.distance_to(center) / radius, 0.0, 1.0)
		apply_hit(enemy, damage, outward, radius * 3.0 * falloff)


func _run_electric_chain(
	start_position: Vector2,
	excluded_ids: Array[int],
	initial_damage: float
) -> void:
	var current_generation := chain_generation
	var visited: Dictionary = {}
	for excluded_id in excluded_ids:
		if excluded_id != 0:
			visited[excluded_id] = true
	var current_position := start_position
	var jump_damage := initial_damage
	var continuation_chance := 0.5

	for jump_index in range(MAX_CHAIN_JUMPS):
		if jump_index > 0:
			if random.randf() > continuation_chance:
				break
			continuation_chance *= 0.5

		var next_target := _find_nearest_enemy(current_position, visited)
		if not is_instance_valid(next_target):
			break
		var target_position := next_target.global_position
		visited[next_target.get_instance_id()] = true
		_spawn_arc_visual(current_position, target_position, jump_index)
		apply_hit(next_target, jump_damage, (target_position - current_position).normalized(), 28.0)
		current_position = target_position
		jump_damage *= 0.5
		if jump_damage < 0.05:
			break
		if jump_index + 1 < MAX_CHAIN_JUMPS and is_inside_tree():
			await get_tree().create_timer(CHAIN_STEP_DELAY, false).timeout
			if current_generation != chain_generation:
				return


func _find_nearest_enemy(origin: Vector2, visited: Dictionary) -> Node2D:
	var nearest: Node2D
	var nearest_distance_squared := CHAIN_RANGE * CHAIN_RANGE
	for enemy_node in get_tree().get_nodes_in_group(&"minotaurs"):
		if not _is_valid_enemy(enemy_node):
			continue
		var enemy := enemy_node as Node2D
		if visited.has(enemy.get_instance_id()):
			continue
		var distance_squared := origin.distance_squared_to(enemy.global_position)
		if distance_squared <= nearest_distance_squared:
			nearest = enemy
			nearest_distance_squared = distance_squared
	return nearest


func _is_valid_enemy(enemy_node: Node) -> bool:
	return (
		is_instance_valid(enemy_node)
		and not enemy_node.is_queued_for_deletion()
		and enemy_node.has_method(&"take_damage")
		and enemy_node.has_method(&"is_alive")
		and bool(enemy_node.call(&"is_alive"))
	)


func _spawn_arc_visual(
	from_position: Vector2,
	to_position: Vector2,
	variant_index: int
) -> void:
	var arc := ELECTRIC_ARC_SCENE.instantiate() as Node2D
	add_child(arc)
	arc.call(&"setup", from_position, to_position, variant_index % 2 == 1)


func _spawn_explosion_visual(center: Vector2, radius: float) -> void:
	var explosion := ELECTRIC_EXPLOSION_SCENE.instantiate() as Node2D
	add_child(explosion)
	explosion.call(&"setup", center, radius)
