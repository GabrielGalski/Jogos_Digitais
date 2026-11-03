extends CharacterBody2D
## Ground-plane actor. Hover, shot recoil and death expansion are visual only.
signal died(actor: Node2D)
signal damaged(amount: float, remaining_health: float)

const VISUAL: Script = preload("res://scripts/visual/flying_eye_visual.gd")
var profile: FlyingEyeProfile
var health: float = 6.0
var desired_velocity: Vector2 = Vector2.ZERO
var hit_velocity: Vector2 = Vector2.ZERO
var floor_height: float = 0.0
var phase: float = 0.0
var home_position: Vector2 = Vector2.ZERO
var dying: bool = false
var height_query: Callable = Callable()
var visual: Sprite2D = null
var _shadow: Polygon2D = null
var _movement_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	if profile == null: profile = FlyingEyeProfile.new()
	health = profile.maximum_health
	collision_layer = 4
	collision_mask = 5
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.02
	z_index = 2
	add_to_group(&"enemy_bodies")
	add_to_group(&"enemy_ai_actor")
	add_to_group(&"flying_eyes")
	set_meta(&"enemy_ai_role", EnemyAIEnums.Role.RANGED)
	set_meta(&"enemy_ai_is_attacking", false)
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = profile.body_radius
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.name = "BodyCollision"
	shape.shape = circle
	add_child(shape)
	_shadow = Polygon2D.new()
	_shadow.name = "Shadow"
	_shadow.color = Color(0.145, 0.075, 0.102, 0.38)
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(16): points.append(Vector2.from_angle(i * TAU / 16.0) * Vector2(5.5, 2.2))
	_shadow.polygon = points
	_shadow.z_index = -1
	_shadow.position.y = -floor_height
	add_child(_shadow)
	visual = VISUAL.new() as Sprite2D
	visual.name = "Sprite"
	visual.set("phase", phase)
	visual.set("floor_height", floor_height)
	add_child(visual)
	visual.connect("death_finished", queue_free)


func _physics_process(delta: float) -> void:
	if dying: return
	hit_velocity = hit_velocity.move_toward(Vector2.ZERO, 340.0 * delta)
	_movement_velocity = _movement_velocity.move_toward(desired_velocity, profile.acceleration * delta)
	velocity = _movement_velocity + hit_velocity
	move_and_slide()
	if height_query.is_valid(): floor_height = float(height_query.call(global_position))
	visual.set("floor_height", floor_height)
	_shadow.position.y = -floor_height


func get_combat_faction() -> StringName:
	return &"monsters"


func is_alive() -> bool:
	return not dying and health > 0.0


func get_current_health() -> float:
	return health


func get_separation_radius() -> float:
	return profile.body_radius


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": Vector2(0, -8.0 - floor_height), "radius": 7.0, "height": 16.0}


func take_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0: return
	health = maxf(health - amount, 0.0)
	visual.call("flash_hit")
	damaged.emit(amount, health)
	if health <= 0.0:
		dying = true
		_stop_combat()
		_shadow.hide()
		visual.call("begin_death")
		died.emit(self)


func receive_impact(direction: Vector2, impulse: float, _recovery: float = 0.055) -> void:
	if is_alive(): hit_velocity = (hit_velocity + direction.normalized() * impulse * 0.45).limit_length(65.0)


func aim(direction: Vector2, preparing: bool = false) -> void:
	if not is_alive(): return
	visual.set("look_direction", direction)
	visual.set("preparing", preparing)


func shoot_recoil(direction: Vector2) -> void:
	if is_alive(): visual.call("shot_recoil", direction)


func dismiss() -> void:
	_stop_combat()
	dying = true
	queue_free()


func _stop_combat() -> void:
	desired_velocity = Vector2.ZERO
	_movement_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	set_meta(&"enemy_ai_is_attacking", false)
	for group: StringName in [&"enemy_bodies", &"enemy_ai_actor", &"flying_eyes"]:
		remove_from_group(group)
