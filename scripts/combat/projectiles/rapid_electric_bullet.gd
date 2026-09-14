extends Area2D
class_name RapidElectricBullet

@export var movement_speed := 180.0
@export var direct_damage := 1.0
@export var chain_damage := 4.0
@export var explosion_radius := 18.0
@export var explosion_damage := 1.0
@export var maximum_lifetime := 1.4

var direction := Vector2.RIGHT
var remaining_lifetime := 1.4
var combat_effects: CombatEffects
var consumed := false


func _ready() -> void:
	remaining_lifetime = maximum_lifetime
	body_entered.connect(_on_body_entered)
	add_to_group(&"player_projectiles")


func setup(shot_direction: Vector2, effects: CombatEffects) -> void:
	direction = shot_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	combat_effects = effects
	rotation = direction.angle()
	# Silhueta direcional mais rápida, mantendo o sprite e a colisão existentes.
	$Sprite.scale = Vector2(0.88, 0.56)


func _physics_process(delta: float) -> void:
	if consumed or is_queued_for_deletion():
		return
	var next_position: Vector2 = global_position + direction * movement_speed * delta
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, next_position, 4)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_on_body_entered(hit["collider"] as Node2D)
		if consumed:
			return
	global_position = next_position
	remaining_lifetime -= delta
	if remaining_lifetime <= 0.0:
		queue_free()


func _on_body_entered(area: Node2D) -> void:
	if consumed or is_queued_for_deletion() or not area.is_in_group(&"minotaurs"):
		return
	if not area.has_method(&"is_alive") or not bool(area.call(&"is_alive")):
		return
	consumed = true
	set_deferred(&"monitoring", false)
	var hit_position := area.global_position
	if is_instance_valid(combat_effects):
		combat_effects.apply_hit(area, direct_damage, direction, 105.0)
		combat_effects.trigger_primary_modifiers(
			area,
			hit_position,
			chain_damage,
			explosion_radius,
			explosion_damage
		)
	queue_free()

