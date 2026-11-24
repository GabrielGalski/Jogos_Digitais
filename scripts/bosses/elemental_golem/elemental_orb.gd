extends Node2D
## Continuous contacts, accelerated return to the caster, one damage event per orb.

signal damage_dealt(amount: float)
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const HORDE: Script = preload("res://scripts/enemies/open_world_horde_catalog.gd")
const LIGHTNING_BOLT: Texture2D = preload("res://assets/enemies/golem/effects/lightning_bolt.png")

var target: Player = null
var caster: Node2D = null
var element: int = 0
var direction: Vector2 = Vector2.RIGHT
var speed: float = 126.0
var radius: float = 4.0
var reflected_damage: float = 30.0
var reflected: bool = false
var consumed: bool = false
var remaining: float = 7.0
var _age: float = 0.0
var _previous_target: Vector2 = Vector2.ZERO
var _art: Sprite2D


func _ready() -> void:
	add_to_group(&"enemy_projectiles")
	add_to_group(&"parryable_projectiles")
	add_to_group(&"elemental_golem_orbs")
	z_index = 8
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_art = Sprite2D.new()
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.position = Vector2(0, -9)
	if element == 2:
		_art.texture = LIGHTNING_BOLT
		_art.hframes = 4
	else:
		var shot: Dictionary = HORDE.TYPES["batilisk" if element == 1 else "lizard_monk"]
		_art.texture = shot["shot"] as Texture2D
		_art.hframes = int(shot["frames"])
	add_child(_art)
	_update_art()
	if is_instance_valid(target): _previous_target = target.global_position


func _physics_process(delta: float) -> void:
	if consumed: return
	_age += delta
	remaining -= delta
	if remaining <= 0.0 or not is_instance_valid(target) or target.dead or target.intro_locked:
		dismiss()
		return
	var origin: Vector2 = global_position
	var return_capsule: Dictionary = {}
	if reflected and is_instance_valid(caster) and bool(caster.call("is_alive")):
		# A returned orb stays on its owner even if it begins a platform jump.
		return_capsule = caster.call("get_projectile_hurt_capsule") as Dictionary
		return_capsule["center"] = caster.to_global(return_capsule.get("center",Vector2.ZERO) as Vector2)
		direction = global_position.direction_to(return_capsule.center as Vector2)
	var endpoint: Vector2 = origin + direction * speed * delta
	var wall_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, endpoint, 1)
	var wall: Dictionary = get_world_2d().direct_space_state.intersect_ray(wall_query)
	var wall_fraction: float = origin.distance_to(wall.get("position", endpoint) as Vector2) / maxf(origin.distance_to(endpoint), 0.001) if not wall.is_empty() else 1.01
	if reflected:
		if not is_instance_valid(caster) or not bool(caster.call("is_alive")):
			dismiss()
			return
		var body_radius: float = float(return_capsule.get("radius",21.0))
		var stem: float = maxf(0.0,float(return_capsule.get("height",52.0))*0.5-body_radius)
		var hit: Dictionary = CONTACTS.capsule_hit(origin, endpoint, return_capsule.center as Vector2, body_radius+radius, stem)
		if not hit.is_empty() and float(hit.fraction) <= wall_fraction:
			target.apply_reflected_damage(caster, reflected_damage, direction)
			dismiss()
			return
	elif not target.is_dashing():
		var hit: Dictionary = CONTACTS.capsule_hit(origin - _previous_target, endpoint - target.global_position, Vector2(0,3), radius + 6.0, 4.0)
		if not hit.is_empty() and float(hit.fraction) <= wall_fraction:
			global_position = origin.lerp(endpoint, float(hit.fraction))
			if target.try_parry_projectile(self): return
			var before: float = target.health
			target.receive_projectile_damage(maxi(1, roundi(target.max_health * 0.05)), caster if is_instance_valid(caster) else null)
			var dealt: float = before - target.health
			if dealt > 0.0: damage_dealt.emit(dealt)
			dismiss()
			return
	if not wall.is_empty():
		dismiss()
		return
	global_position = endpoint
	_previous_target = target.global_position
	_update_art()


func parry(reflector: Player) -> bool:
	if consumed or reflected or reflector != target: return false
	reflected = true
	speed = maxf(speed * 2.5, 340.0)
	remaining = 4.0
	direction = global_position.direction_to(caster.global_position) if is_instance_valid(caster) else -direction
	remove_from_group(&"enemy_projectiles")
	remove_from_group(&"parryable_projectiles")
	if is_instance_valid(_art):
		_art.self_modulate = Color(1.2, 1.2, 1.2)
		_update_art()
	return true


func dismiss() -> void:
	if consumed: return
	consumed = true
	set_physics_process(false)
	queue_free()


func _update_art() -> void:
	var fps: float = 24.0 if reflected else 16.0
	_art.frame = int(_age * fps) % _art.hframes
	_art.rotation = direction.angle()
