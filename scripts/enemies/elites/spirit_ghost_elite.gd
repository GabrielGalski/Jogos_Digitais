extends Area2D
class_name SpiritGhostElite

const FLEE_DIRECTION_SAMPLES := 16

@export var movement_speed := 34.0
@export var max_resistance := 16
@export var separation_radius := 24.0
@export var separation_weight := 1.8

@onready var sprite: AnimatedSprite2D = $Sprite

var target: Player
var movement_bounds := Rect2(-Vector2(300.0, 150.0), Vector2(600.0, 300.0))
var resistance := 16
var last_move_direction := Vector2.RIGHT


func _ready() -> void:
	resistance = max_resistance
	add_to_group(&"spirit_ghost_elite")
	add_to_group(&"enemy_bodies")
	sprite.play(&"move")


func setup(player: Player, arena_bounds: Rect2) -> void:
	target = player
	movement_bounds = arena_bounds


func get_separation_radius() -> float:
	return separation_radius


func take_damage(amount: int) -> void:
	resistance -= maxi(amount, 0)
	if resistance <= 0:
		queue_free()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return

	var safe_bounds := movement_bounds.grow(-separation_radius)
	var direction := _choose_flee_direction(safe_bounds, delta)
	var separation := _get_separation_vector()
	if not separation.is_zero_approx():
		direction = (direction + separation * separation_weight).normalized()

	var candidate := global_position + direction * movement_speed * delta
	candidate = _resolve_minimum_spacing(candidate)
	global_position = candidate.clamp(safe_bounds.position, safe_bounds.end)
	last_move_direction = direction
	if absf(direction.x) > 0.05:
		sprite.flip_h = direction.x < 0.0


func _choose_flee_direction(safe_bounds: Rect2, delta: float) -> Vector2:
	var best_direction := last_move_direction
	var best_score := -INF
	for sample in range(FLEE_DIRECTION_SAMPLES):
		var direction := Vector2.from_angle(TAU * float(sample) / FLEE_DIRECTION_SAMPLES)
		var candidate := global_position + direction * movement_speed * delta
		if not safe_bounds.has_point(candidate):
			continue
		var distance_score := candidate.distance_to(target.global_position)
		var edge_clearance := minf(
			minf(candidate.x - safe_bounds.position.x, safe_bounds.end.x - candidate.x),
			minf(candidate.y - safe_bounds.position.y, safe_bounds.end.y - candidate.y)
		)
		var inertia_score := direction.dot(last_move_direction) * 4.0
		var score := distance_score + maxf(edge_clearance, 0.0) * 0.18 + inertia_score
		if score > best_score:
			best_score = score
			best_direction = direction
	return best_direction


func _get_separation_vector() -> Vector2:
	var separation := Vector2.ZERO
	for node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		if node == self or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var other := node as Node2D
		var offset := global_position - other.global_position
		var distance := offset.length()
		var required_distance := _required_center_distance(other)
		if distance >= required_distance:
			continue
		separation += _spacing_normal(offset, other) * (1.0 - distance / required_distance)
	return separation


func _resolve_minimum_spacing(candidate: Vector2) -> Vector2:
	for _pass in range(2):
		for node in get_tree().get_nodes_in_group(&"enemy_bodies"):
			if node == self or not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			var other := node as Node2D
			var offset := candidate - other.global_position
			var distance := offset.length()
			var required_distance := _required_center_distance(other)
			if distance < required_distance:
				candidate = (
					other.global_position
					+ _spacing_normal(offset, other) * required_distance
				)
	return candidate


func _required_center_distance(other: Node2D) -> float:
	var other_radius := separation_radius
	if other.has_method(&"get_separation_radius"):
		other_radius = float(other.call(&"get_separation_radius"))
	return separation_radius + other_radius


func _spacing_normal(offset: Vector2, other: Node2D) -> Vector2:
	if offset.length_squared() > 0.0001:
		return offset.normalized()
	var deterministic_angle := (
		float((get_instance_id() + other.get_instance_id()) % 360) * PI / 180.0
	)
	return Vector2.from_angle(deterministic_angle)
