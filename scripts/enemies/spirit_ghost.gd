extends Area2D
class_name SpiritGhost

signal contact_attack(damage: int)

@export var movement_speed := 44.0
@export var max_resistance := 1
@export var contact_damage := 1
@export var proximity_radius := 9.0
@export var separation_radius := 10.0
@export var separation_weight := 1.6
@export var empowered_speed_multiplier := 1.5
@export var empowered_damage := 2
@export var empowered_scale := 1.15
@export var empowered_separation_radius := 12.0

@onready var sprite: AnimatedSprite2D = $Sprite

var target: Player
var resistance := 1
var elapsed := 0.0
var float_phase := 0.0
var attack_consumed := false
var empowered := false


func _ready() -> void:
	resistance = max_resistance
	float_phase = randf() * TAU
	add_to_group(&"spirit_ghosts")
	add_to_group(&"enemy_bodies")
	body_entered.connect(_on_body_entered)
	sprite.play(&"move")


func setup(player: Player, speed: float, should_empower: bool = false) -> void:
	target = player
	movement_speed = speed
	if should_empower:
		empower()


func empower() -> void:
	if empowered or attack_consumed:
		return
	empowered = true
	movement_speed *= empowered_speed_multiplier
	contact_damage = empowered_damage
	max_resistance = maxi(max_resistance, 2)
	resistance = maxi(resistance, max_resistance)
	proximity_radius = maxf(proximity_radius, 10.0)
	separation_radius = empowered_separation_radius
	sprite.scale = Vector2.ONE * empowered_scale
	sprite.play(&"empowered_move")
	add_to_group(&"empowered_spirit_ghosts")


func is_empowered() -> bool:
	return empowered


func get_separation_radius() -> float:
	return separation_radius


func take_damage(amount: int) -> void:
	if attack_consumed:
		return
	resistance -= maxi(amount, 0)
	if resistance <= 0:
		attack_consumed = true
		queue_free()


func _physics_process(delta: float) -> void:
	if attack_consumed or not is_instance_valid(target):
		return

	elapsed += delta
	var to_target := target.global_position - global_position
	if to_target.length_squared() > 0.001:
		var chase_direction := to_target.normalized()
		var separation := _get_separation_vector()
		var direction := (chase_direction + separation * separation_weight).normalized()
		var next_position := global_position + direction * movement_speed * delta
		global_position = _resolve_minimum_spacing(next_position)
		# O desenho-base olha para a esquerda.
		sprite.flip_h = direction.x > 0.0

	# Movimento etereo independente dos quatro frames do sprite.
	sprite.position.y = sin(elapsed * 3.2 + float_phase) * 0.65

	# A verificacao por distancia garante o ataque mesmo em frames com deslocamento maior.
	if global_position.distance_squared_to(target.global_position) <= proximity_radius * proximity_radius:
		_consume_on_contact()


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
		var normal := _spacing_normal(offset, other)
		separation += normal * (1.0 - distance / required_distance)
	return separation


func _resolve_minimum_spacing(candidate: Vector2) -> Vector2:
	# Duas passagens corrigem sobreposicoes criadas por correcoes contra outro vizinho.
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
	var deterministic_angle := float((get_instance_id() + other.get_instance_id()) % 360) * PI / 180.0
	return Vector2.from_angle(deterministic_angle)


func _on_body_entered(body: Node2D) -> void:
	if body == target:
		_consume_on_contact()


func _consume_on_contact() -> void:
	if attack_consumed:
		return
	attack_consumed = true
	contact_attack.emit(contact_damage)
	if target.has_method(&"receive_contact_damage"):
		target.receive_contact_damage(contact_damage)
	set_physics_process(false)
	queue_free()
