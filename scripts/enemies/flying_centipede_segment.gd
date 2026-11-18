extends Node2D
## A flight joint with independent health and a projectile capsule in sprite space.
signal broken(segment: Node2D)

const MAX_HEALTH: float = 3.0
const FLASH_SHADER: Shader = preload("res://shaders/white_damage_flash.gdshader")

var health: float = MAX_HEALTH
var last_hit_direction: Vector2 = Vector2.UP
var final_segment: bool = false
var art: Sprite2D
var _flash: float = 0.0
var _material: ShaderMaterial


func _ready() -> void:
	set_meta(&"is_boss", true)
	add_to_group(&"enemy_bodies")
	_material = ShaderMaterial.new()
	_material.shader = FLASH_SHADER
	art.material = _material
	set_process(false)


func is_alive() -> bool:
	return health > 0.0 and not is_queued_for_deletion()


func get_current_health() -> float:
	return health


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": Vector2.ZERO, "radius": 8.0, "height": 18.0}


func receive_impact(direction: Vector2, _impulse: float, _recovery: float = 0.0) -> void:
	if not direction.is_zero_approx():
		last_hit_direction = direction.normalized()


func counts_as_kill() -> bool:
	return final_segment


func take_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_flash = 0.12
	_material.set_shader_parameter(&"flash_amount", 1.0)
	set_process(true)
	if health <= 0.0:
		remove_from_group(&"enemy_bodies")
		broken.emit(self)
		var fade: Tween = create_tween()
		fade.tween_property(self, "modulate:a", 0.0, 0.14)
		fade.tween_callback(queue_free)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_material.set_shader_parameter(&"flash_amount", clampf(_flash * 14.0, 0.0, 1.0))
	art.scale = Vector2(1.0 + _flash, 1.0 - _flash)
	set_process(_flash > 0.0)
