extends Area2D
class_name Minotaur

const MINOTAUR_MELEE_ATTACK_SCENE := preload(
	"res://scenes/enemies/attacks/minotaur_melee_attack.tscn"
)
const MELEE_EFFECT_OFFSET := 17.0

enum State {
	CHASING,
	ATTACKING,
}

@export var movement_speed := 38.0
@export var max_resistance := 6
@export var attack_range := 44.0
@export var attack_exit_range := 51.0
@export var attack_interval := 2.0
@export var attack_windup := 0.38
@export var separation_radius := 13.0
@export var separation_weight := 1.5

@onready var sprite: AnimatedSprite2D = $Sprite

var target: Player
var movement_bounds := Rect2(-Vector2(300.0, 150.0), Vector2(600.0, 300.0))
var resistance := 6
var state := State.CHASING
var attack_cycle_remaining := 0.0
var attack_windup_elapsed := 0.0
var shot_pending := false


func _ready() -> void:
	resistance = max_resistance
	add_to_group(&"minotaurs")
	add_to_group(&"enemy_bodies")
	sprite.play(&"walk")


func setup(player: Player, arena_bounds: Rect2) -> void:
	target = player
	movement_bounds = arena_bounds


func get_separation_radius() -> float:
	return separation_radius


func get_state_name() -> StringName:
	return &"attack" if state == State.ATTACKING else &"walk"


func take_damage(amount: int) -> void:
	resistance -= maxi(amount, 0)
	if resistance <= 0:
		queue_free()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var target_distance := to_target.length()
	_update_facing(to_target)

	if state == State.ATTACKING:
		if target_distance > attack_exit_range:
			_enter_chasing()
			_chase_target(delta, to_target)
		else:
			_update_attack(delta)
		return

	if target_distance <= attack_range:
		_enter_attacking()
		_update_attack(delta)
	else:
		_chase_target(delta, to_target)


func _enter_chasing() -> void:
	state = State.CHASING
	shot_pending = false
	attack_cycle_remaining = 0.0
	attack_windup_elapsed = 0.0
	sprite.play(&"walk")


func _enter_attacking() -> void:
	state = State.ATTACKING
	_begin_attack_cycle()


func _begin_attack_cycle() -> void:
	attack_cycle_remaining = attack_interval
	attack_windup_elapsed = 0.0
	shot_pending = true
	sprite.play(&"attack")


func _update_attack(delta: float) -> void:
	attack_cycle_remaining -= delta
	if shot_pending:
		attack_windup_elapsed += delta
		if attack_windup_elapsed >= attack_windup:
			shot_pending = false
			_activate_melee_attack()

	if attack_cycle_remaining <= 0.0:
		_begin_attack_cycle()


func _chase_target(delta: float, to_target: Vector2) -> void:
	if to_target.is_zero_approx():
		return

	var direction := to_target.normalized()
	var separation := _get_separation_vector()
	if not separation.is_zero_approx():
		direction = (direction + separation * separation_weight).normalized()

	var safe_bounds := movement_bounds.grow(-separation_radius)
	var candidate := global_position + direction * movement_speed * delta
	candidate = _resolve_minimum_spacing(candidate)
	global_position = candidate.clamp(safe_bounds.position, safe_bounds.end)


func _update_facing(to_target: Vector2) -> void:
	if absf(to_target.x) > 0.05:
		# Todos os sprites fornecidos olham para a direita.
		sprite.flip_h = to_target.x < 0.0


func _activate_melee_attack() -> void:
	if not is_instance_valid(target) or not is_inside_tree():
		return

	var attack_direction := (target.global_position - global_position).normalized()
	if attack_direction.is_zero_approx():
		attack_direction = Vector2.LEFT if sprite.flip_h else Vector2.RIGHT

	var melee_attack := MINOTAUR_MELEE_ATTACK_SCENE.instantiate() as Node2D
	add_child(melee_attack)
	melee_attack.position = attack_direction * MELEE_EFFECT_OFFSET
	melee_attack.call(&"setup", target, self, attack_direction, attack_range)


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
