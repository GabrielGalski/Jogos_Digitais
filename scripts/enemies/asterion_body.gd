extends CharacterBody2D
## Damage receiver located at the moving actor, independently of the throne.
var last_hit_direction: Vector2 = Vector2.RIGHT
@export_category("Projectile contact")
@export var projectile_hurt_radius: float = 18.0
@export var projectile_hurt_height: float = 54.0
@export var projectile_hurt_offset: Vector2 = Vector2(0, -14)

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


func get_projectile_hurt_capsule() -> Dictionary:
	# Foot collision remains 12 px; the separate receiving volume covers the torso too.
	return {"center": projectile_hurt_offset, "radius": projectile_hurt_radius, "height": projectile_hurt_height}

func get_separation_radius() -> float:
	var collider: CollisionShape2D = $BodyCollision
	var circle: CircleShape2D = collider.shape as CircleShape2D
	return circle.radius * global_scale.x if circle != null else 12.0
