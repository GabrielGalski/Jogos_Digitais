extends CharacterBody2D
## Wall-phasing spirit. Only other enemy bodies occupy its movement mask.
signal died(enemy: Node2D)
signal consumed(enemy: Node2D)
signal damaged(amount: float, remaining_health: float)

const FRAMES: Array[Texture2D] = [
	preload("res://assets/enemies/spirit/normal/spirit_ghost_move_01.png"),
	preload("res://assets/enemies/spirit/normal/spirit_ghost_move_02.png"),
	preload("res://assets/enemies/spirit/normal/spirit_ghost_move_03.png"),
	preload("res://assets/enemies/spirit/normal/spirit_ghost_move_04.png"),
]
const BODY_RADIUS: float = 7.0
const HURT_CENTER: Vector2 = Vector2(0, -7)
static var _texture_centers: Dictionary[Texture2D, Vector2] = {}
var remains_system: Node2D = null
var resistance: float = 3.0
var max_resistance: float = 3.0
var movement_speed: float = 48.0
var contact_damage: int = 3
var sway_strength: float = 0.0
var difficulty_stage: int = 0
var phase: float = 0.0
var last_hit_direction: Vector2 = Vector2.RIGHT
var hit_velocity: Vector2 = Vector2.ZERO
var dying: bool = false
var _sprite: Sprite2D = null
var _flash: float = 0.0
var _age: float = 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.02
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group(&"enemy_bodies")
	add_to_group(&"spirit_ghosts")
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.name = "BodyCollision"
	collider.shape = shape
	add_child(collider)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.position = Vector2(0, -7)
	_sprite.texture = FRAMES[0]
	var flash: ShaderMaterial = ShaderMaterial.new()
	flash.shader = preload("res://shaders/white_damage_flash.gdshader")
	_sprite.material = flash
	add_child(_sprite)


func apply_profile(profile: Resource, stage: int, initialize_health: bool = false) -> void:
	difficulty_stage = clampi(stage, 0, 3)
	max_resistance = float(profile.call("health"))
	if initialize_health:
		resistance = max_resistance
	movement_speed = float(profile.call("speed", difficulty_stage))
	contact_damage = int(profile.call("damage", difficulty_stage))
	sway_strength = float(profile.call("sway", difficulty_stage))


func _process(delta: float) -> void:
	_age += delta
	_flash = maxf(0.0, _flash - delta * 9.0)
	(_sprite.material as ShaderMaterial).set_shader_parameter(&"flash_amount", _flash)
	_sprite.texture = FRAMES[posmod(int((_age + phase) * (8.0 + difficulty_stage)), FRAMES.size())]
	if absf(velocity.x) > 1.0:
		_sprite.flip_h = velocity.x < 0.0


func is_alive() -> bool:
	return not dying and resistance > 0.0


func get_current_health() -> float:
	return resistance


func get_separation_radius() -> float:
	return BODY_RADIUS + 1.0


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": HURT_CENTER, "radius": 6.0, "height": 18.0}


func take_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0:
		return
	resistance = maxf(0.0, resistance - amount)
	_flash = 0.8
	damaged.emit(amount, resistance)
	if resistance <= 0.0:
		_disappear(true)


func receive_impact(direction: Vector2, impulse: float, _recovery: float = 0.055) -> void:
	if not is_alive():
		return
	last_hit_direction = direction.normalized()
	hit_velocity = (hit_velocity + last_hit_direction * impulse).limit_length(130.0)


func consume_on_contact() -> void:
	if is_alive():
		_disappear(false)


func dismiss() -> void:
	if is_alive():
		_disappear(false)


func get_visual_center_of_mass() -> Vector2:
	if _sprite == null or _sprite.texture == null:
		return to_global(HURT_CENTER)
	var texture: Texture2D = _sprite.texture
	if not _texture_centers.has(texture):
		var image: Image = texture.get_image()
		var total: float = 0.0
		var weighted: Vector2 = Vector2.ZERO
		if image != null:
			if image.is_compressed():
				image.decompress()
			for y: int in range(image.get_height()):
				for x: int in range(image.get_width()):
					var alpha: float = image.get_pixel(x, y).a
					weighted += Vector2(x + 0.5, y + 0.5) * alpha
					total += alpha
		_texture_centers[texture] = weighted / total - texture.get_size() * 0.5 if total > 0.0 else Vector2.ZERO
	var center: Vector2 = _texture_centers[texture]
	if _sprite.flip_h:
		center.x = -center.x
	return _sprite.to_global(center)


func _disappear(killed: bool) -> void:
	dying = true
	if killed and is_instance_valid(remains_system):
		# Emit before changing pose/velocity and before the encounter can finish itself.
		remains_system.call("emit_spirit", get_visual_center_of_mass(), global_position, last_hit_direction, velocity + hit_velocity)
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	remove_from_group(&"enemy_bodies")
	remove_from_group(&"spirit_ghosts")
	if killed:
		died.emit(self)
	else:
		consumed.emit(self)
	# Small native sprite fade; no spawn markers, counters or death beams.
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.10)
	fade.tween_callback(queue_free)
