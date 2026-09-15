extends CharacterBody2D
## Damage receiver located at the moving actor, independently of the throne.
var last_hit_direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	add_to_group(&"enemy_bodies")

func is_alive() -> bool:
	return get_parent().can_receive_damage()

func take_damage(amount: float) -> void:
	get_parent().take_damage(amount)

func receive_impact(direction: Vector2, _impulse: float, _recovery: float = 0.055) -> void:
	last_hit_direction = direction

func get_current_health() -> float:
	return get_parent().health
