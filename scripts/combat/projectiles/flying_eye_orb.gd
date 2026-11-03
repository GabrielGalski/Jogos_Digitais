extends Node2D
## Swept red orb. Monster shots ignore monster bodies; parry changes ownership.

const AFFILIATION: Script = preload("res://scripts/combat/combat_affiliation.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
var target: Player = null
var shooter: Node2D = null
var pack_id: int = 0
var faction: StringName = &"monsters"
var direction: Vector2 = Vector2.RIGHT
var speed: float = 116.0
var damage: int = 3
var radius: float = 3.0
var remaining: float = 3.4
var height_query: Callable = Callable()
var reflected: bool = false
var consumed: bool = false
var _visual_height: float = 0.0
var _age: float = 0.0
var _previous_target: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group(&"enemy_projectiles")
	add_to_group(&"parryable_projectiles")
	add_to_group(&"flying_eye_orbs")
	z_index = 3
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var unlit: CanvasItemMaterial = CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unlit
	if is_instance_valid(target): _previous_target = target.global_position


func _physics_process(delta: float) -> void:
	if consumed: return
	remaining -= delta
	_age += delta
	if remaining <= 0.0 or not is_instance_valid(target) or target.dead or target.intro_locked:
		dismiss()
		return
	var endpoint: Vector2 = global_position + direction * speed * delta
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, endpoint, 5 if reflected else 1)
	query.exclude = [target.get_rid()]
	if not reflected and is_instance_valid(shooter) and shooter is CollisionObject2D:
		query.exclude.append((shooter as CollisionObject2D).get_rid())
	var hit: Dictionary = space.intersect_ray(query)
	var wall_fraction: float = global_position.distance_to(hit.get("position", endpoint) as Vector2) / maxf(global_position.distance_to(endpoint), 0.001) if not hit.is_empty() else 1.01
	if not reflected and not target.is_dashing():
		var capsule: CapsuleShape2D = (target.get_node("CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
		var offset: Vector2 = (target.get_node("CollisionShape2D") as CollisionShape2D).position
		var contact: Dictionary = CONTACTS.capsule_hit(global_position - _previous_target, endpoint - target.global_position,
			offset, capsule.radius + radius, capsule.height * 0.5 - capsule.radius)
		if not contact.is_empty() and float(contact.fraction) <= wall_fraction:
			global_position = global_position.lerp(endpoint, float(contact.fraction))
			if target.try_parry_projectile(self): return
			if AFFILIATION.can_damage(faction, target): target.receive_projectile_damage(damage)
			dismiss()
			return
	if not hit.is_empty():
		global_position = hit.position as Vector2
		var body: Node = hit.get("collider") as Node
		if reflected and AFFILIATION.can_damage(faction, body) and body.has_method("take_damage"):
			body.call("take_damage", float(damage))
		dismiss()
		return
	global_position = endpoint
	_previous_target = target.global_position
	_visual_height = float(height_query.call(global_position)) if height_query.is_valid() else _visual_height
	queue_redraw()


func parry(reflector: Player) -> bool:
	if consumed or reflected or reflector != target: return false
	reflected = true
	faction = &"player"
	damage = 30
	speed *= 1.35
	direction = global_position.direction_to(shooter.global_position) if is_instance_valid(shooter) and shooter.has_method("is_alive") and bool(shooter.call("is_alive")) else -direction
	remove_from_group(&"enemy_projectiles")
	queue_redraw()
	return true


func dismiss() -> void:
	if consumed: return
	consumed = true
	set_physics_process(false)
	queue_free()


func _draw() -> void:
	var center: Vector2 = Vector2(0, -8.0 - _visual_height)
	var pulse: float = 0.12 * sin(_age * 11.0)
	draw_circle(center, radius + 3.0, Color(0.95, 0.14, 0.23, 0.13))
	draw_circle(center, radius + 0.7 + pulse, Color("#49172e"))
	draw_circle(center, radius + pulse, Color("#f2384e"))
	draw_circle(center + Vector2(-0.45, -0.55), 1.15, Color.WHITE if reflected else Color("#ffb8a5"))
