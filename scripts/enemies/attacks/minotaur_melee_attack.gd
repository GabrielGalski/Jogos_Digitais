extends Area2D
class_name MinotaurMeleeAttack

@export var contact_damage := 2
@export var lifetime := 0.45

@onready var sprite: AnimatedSprite2D = $Sprite

var target: Player
var attacker: Node2D
var attack_direction := Vector2.RIGHT
var melee_reach := 44.0
var knockback_force: float = 0.0
var elapsed := 0.0
var consumed := false


func _ready() -> void:
	add_to_group(&"minotaur_melee_attacks")
	body_entered.connect(_on_body_entered)
	sprite.play(&"attack_effect")


func setup(
	player: Player,
	source: Node2D,
	direction: Vector2,
	reach: float,
	knockback: float = 0.0
) -> void:
	target = player
	attacker = source
	attack_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	melee_reach = reach
	knockback_force = knockback
	rotation = attack_direction.angle()


func _physics_process(delta: float) -> void:
	if consumed:
		return

	elapsed += delta
	if elapsed >= lifetime:
		_expire()
		return

	if not is_instance_valid(target) or not is_instance_valid(attacker):
		return

	var attacker_to_target := target.global_position - attacker.global_position
	var target_distance := attacker_to_target.length()
	var inside_front_half := (
		target_distance <= 0.001
		or attacker_to_target.normalized().dot(attack_direction) >= 0.0
	)
	if target_distance <= melee_reach and inside_front_half:
		_hit_player()


func _on_body_entered(body: Node2D) -> void:
	if body == target:
		_hit_player()


func _hit_player() -> void:
	if consumed:
		return
	if not is_instance_valid(attacker) or not attacker.is_alive() or target.intro_locked:
		return
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(attacker.global_position, target.global_position, 1)
	query.exclude = [target.get_rid(), (attacker as CharacterBody2D).get_rid()]
	if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		return
	consumed = true
	if target.has_method(&"receive_contact_damage"):
		target.receive_contact_damage(contact_damage, attack_direction, knockback_force)
	set_physics_process(false)
	queue_free()


func _expire() -> void:
	if consumed:
		return
	consumed = true
	set_physics_process(false)
	queue_free()

