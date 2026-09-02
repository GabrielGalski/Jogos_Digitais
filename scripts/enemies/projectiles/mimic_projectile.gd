extends Area2D
class_name MimicProjectile

@export var movement_speed := 112.0
@export var contact_damage := 2
@export var lifetime := 5.0

var target: Player
var direction := Vector2.RIGHT
var elapsed := 0.0
var consumed := false


func _ready() -> void:
	add_to_group(&"mimic_projectiles")
	body_entered.connect(_on_body_entered)


func setup(player: Player, shot_direction: Vector2) -> void:
	target = player
	direction = shot_direction.normalized() if not shot_direction.is_zero_approx() else Vector2.RIGHT
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	if consumed:
		return
	elapsed += delta
	if elapsed >= lifetime:
		consumed = true
		queue_free()
		return

	global_position += direction * movement_speed * delta
	if is_instance_valid(target):
		if global_position.distance_squared_to(target.global_position) <= 7.0 * 7.0:
			_hit_player()


func _on_body_entered(body: Node2D) -> void:
	if body == target:
		_hit_player()


func _hit_player() -> void:
	if consumed:
		return
	consumed = true
	if target.has_method(&"receive_contact_damage"):
		target.receive_contact_damage(contact_damage)
	set_physics_process(false)
	queue_free()
