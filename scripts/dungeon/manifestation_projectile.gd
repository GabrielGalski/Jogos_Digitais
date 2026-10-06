extends Area2D
## Shared combat projectile. Presentation listeners are optional and never own damage.
signal visual_impact(at: Vector2, code: StringName)

const M01_A: Texture2D = preload("res://assets/cards/manifestacao/gotas_de_slime M01/projectile/slime_ball.png")
const M01_B: Texture2D = preload("res://assets/cards/manifestacao/gotas_de_slime M01/projectile/slime_ball1.png")
const M02_A: Texture2D = preload("res://assets/cards/manifestacao/massa_de_slime M02/projectile/slime_ball.png")
const M02_B: Texture2D = preload("res://assets/cards/manifestacao/massa_de_slime M02/projectile/slime_ball2.png")
const M01_IMPACT_UPDOWN: Texture2D = preload("res://assets/cards/manifestacao/gotas_de_slime M01/projectile/impact_updown.png")
const M01_IMPACT_LEFT: Texture2D = preload("res://assets/cards/manifestacao/gotas_de_slime M01/projectile/impact_left.png")
const M01_IMPACT_RIGHT: Texture2D = preload("res://assets/cards/manifestacao/gotas_de_slime M01/projectile/impact_right.png")
const M02_IMPACT_UPDOWN: Texture2D = preload("res://assets/cards/manifestacao/massa_de_slime M02/projectile/impact_updown.png")
const M02_IMPACT_LEFT: Texture2D = preload("res://assets/cards/manifestacao/massa_de_slime M02/projectile/impact_left.png")
const M02_IMPACT_RIGHT: Texture2D = preload("res://assets/cards/manifestacao/massa_de_slime M02/projectile/impact_right.png")
const SLIME_IMPACT_DURATION: float = 0.08
const M05_FALL: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/falling/drop_falling.png")
const M05_WALK_1: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/walk/walk1.png")
const M05_WALK_2: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/walk/walk2.png")
const M05_WALK_3: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/walk/walk3.png")
const M05_WALK_4: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/walk/walk4.png")
const M05_WALK_5: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/walk/walk5.png")
const M05_WALK_6: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/walk/walk6.png")
const M05_WALK_7: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/walk/walk7.png")
const M05_WALK_8: Texture2D = preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/walk/walk8.png")
const M05_BOOM: Array[Texture2D] = [
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion1.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion2.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion3.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion4.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion5.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion6.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion7.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion8.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion9.png"),
	preload("res://assets/cards/manifestacao/brotos_de_fungoide M05/explosion/boom/mush_explosion10.png"),
]
const M06_A: Texture2D = preload("res://assets/cards/manifestacao/cauda_de_manticora M06/projectiles/spike1.png")
const M06_B: Texture2D = preload("res://assets/cards/manifestacao/cauda_de_manticora M06/projectiles/spike2.png")
const M06_C: Texture2D = preload("res://assets/cards/manifestacao/cauda_de_manticora M06/projectiles/spike3.png")
const M07_FRAMES: Array[Texture2D] = [
	preload("res://assets/cards/manifestacao/coracao_de_efreeti M07/projectile/flame1.png"),
	preload("res://assets/cards/manifestacao/coracao_de_efreeti M07/projectile/flame2.png"),
	preload("res://assets/cards/manifestacao/coracao_de_efreeti M07/projectile/flame3.png"),
	preload("res://assets/cards/manifestacao/coracao_de_efreeti M07/projectile/flame4.png"),
	preload("res://assets/cards/manifestacao/coracao_de_efreeti M07/projectile/flame5.png"),
]

@onready var visual: Sprite2D = $Visual
@onready var hit_shape: CollisionShape2D = $HitShape

@export_range(0, 16, 1) var max_ricochets: int = 1
@export_range(1.0, 4.0, 0.05) var wall_bounce_speed_multiplier: float = 1.75
@export_range(4.0, 64.0, 1.0) var m02_blast_radius: float = 28.0

var mode: StringName = &"M01"
var phase: StringName = &"flying"
var direction: Vector2 = Vector2.RIGHT
var frames: Array[Texture2D] = []
var animation_clock: float = 0.0
var lifetime: float = 1.4
var speed: float = 180.0
var damage: float = 3.0
var frame_rate: float = 12.0
var remaining_ricochets: int = 1
var wall_speed_boost_applied: bool = false
var slime_impact_time: float = 0.0
var shooter_body: CollisionObject2D
var hit_ids: Dictionary = {}
var target: Node2D = null
var attached_offset: Vector2 = Vector2.ZERO
var attached_time: float = 0.0
var tick_timer: float = 0.0
var tick_damage: float = 0.0
var fall_time: float = 0.0
var card_attack: CardAttack
var combat_effects: CombatEffects
var consumed: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group(&"manifestation_projectiles")
	hit_shape.shape = hit_shape.shape.duplicate()


func configure(card_code: StringName, shot_direction: Vector2, attack: CardAttack, effects: CombatEffects, shooter: CollisionObject2D = null) -> void:
	card_attack = attack
	combat_effects = effects
	shooter_body = shooter
	mode = card_code
	remaining_ricochets = max_ricochets
	wall_speed_boost_applied = false
	if mode == &"M01" or mode == &"M02":
		# The projectile and its brief impact frame are one visual, never two.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	direction = shot_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	match mode:
		&"M01":
			frames = [M01_A, M01_B]
			visual.scale = Vector2.ONE * 0.8
			_set_radius(3.0)
		&"M02":
			frames = [M02_A, M02_B]
			visual.scale = Vector2.ONE * 1.1875
			_set_radius(5.0)
		&"M05":
			frames = [M05_WALK_1, M05_WALK_2, M05_WALK_3, M05_WALK_4,
				M05_WALK_5, M05_WALK_6, M05_WALK_7, M05_WALK_8]
			phase = &"falling"
			fall_time = 0.10
			visual.scale = Vector2.ONE * 0.45
			_set_radius(2.0)
		&"M06":
			frames = [M06_A, M06_B, M06_C]
			visual.scale = Vector2.ONE * 0.7
			_set_radius(1.5)
		&"M07":
			frames = M07_FRAMES
			frame_rate = 20.0
			visual.scale = Vector2.ONE * 0.9
			_set_radius(3.0)
			physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Numerical behavior comes from the equipped Manifestation snapshot.
	speed = attack.projectile_speed
	damage = attack.damage
	lifetime = attack.projectile_lifetime
	visual.texture = M05_FALL if mode == &"M05" else frames[0]
	rotation = direction.angle() if mode != &"M05" else 0.0
	if mode == &"M06":
		# The authored spike points up (-Y), while aim angles use +X.
		rotation += PI * 0.5


func _set_radius(radius: float) -> void:
	var circle: CircleShape2D = hit_shape.shape as CircleShape2D
	circle.radius = radius


func _physics_process(delta: float) -> void:
	if phase == &"impact_ending":
		slime_impact_time -= delta
		if slime_impact_time <= 0.0:
			queue_free()
		return
	if consumed or is_queued_for_deletion():
		return
	animation_clock += delta
	lifetime -= delta
	if phase == &"burst":
		visual.texture = frames[mini(int(animation_clock * 30.0), frames.size() - 1)]
		if lifetime <= 0.0:
			queue_free()
		return
	if phase == &"attached":
		_update_attached(delta)
		return
	if lifetime <= 0.0001:
		queue_free()
		return
	if phase == &"falling":
		fall_time -= delta
		global_position += Vector2(0.0, 38.0 * delta)
		if fall_time <= 0.0:
			phase = &"flying"
		return
	if mode == &"M05":
		target = _nearest_enemy()
		if is_instance_valid(target):
			direction = global_position.direction_to(target.global_position)
			if global_position.distance_to(target.global_position) <= 14.0:
				_explode_mushroom(target)
				return
		rotation = 0.0
	# A stable first frame makes the small muzzle segment readable.
	var animated_age: float = maxf(0.0, animation_clock - (0.10 if mode == &"M01" else 0.0))
	var frame_index: int = int(animated_age * frame_rate)
	if mode == &"M01":
		frame_index = 0 if animation_clock < 0.10 else frame_index + 1
	if mode == &"M01" or mode == &"M02":
		slime_impact_time = maxf(0.0, slime_impact_time - delta)
		if slime_impact_time <= 0.0:
			visual.texture = frames[frame_index % frames.size()]
			visual.flip_v = false
			rotation = direction.angle()
		_advance_slime(delta)
		return
	visual.texture = frames[frame_index % frames.size()]
	if mode == &"M07":
		_advance_efreeti(delta)
		return
	var next_position: Vector2 = global_position + direction * speed * delta
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, next_position, 4)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_on_body_entered(hit.get("collider") as Node2D)
	if phase == &"flying" and not is_queued_for_deletion():
		global_position = next_position


func _advance_efreeti(delta: float) -> void:
	var endpoint: Vector2 = global_position + direction * speed * delta
	var exclusions: Array[RID] = []
	if is_instance_valid(shooter_body):
		exclusions.append(shooter_body.get_rid())
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, endpoint, 5, exclusions)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = endpoint
		return
	global_position = hit["position"] as Vector2
	var body: Node2D = hit["collider"] as Node2D
	if _valid_enemy(body):
		_on_body_entered(body)
	else:
		visual_impact.emit(global_position, mode)
		consumed = true
		hide()
		queue_free()


func _advance_slime(delta: float) -> void:
	var travel_left: float = speed * delta
	var exclusions: Array[RID] = []
	if is_instance_valid(shooter_body):
		exclusions.append(shooter_body.get_rid())
	# Consume the rest of this physics step after a hit, independent of frame timing.
	while travel_left > 0.001 and not consumed:
		var origin: Vector2 = global_position
		var endpoint: Vector2 = origin + direction * travel_left
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, endpoint, 5, exclusions)
		var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			global_position = endpoint
			break
		var contact: Vector2 = hit["position"] as Vector2
		var normal: Vector2 = (hit["normal"] as Vector2).normalized()
		var body: Node2D = hit["collider"] as Node2D
		travel_left -= origin.distance_to(contact)
		if normal.is_zero_approx():
			global_position = contact
			break
		if mode == &"M02":
			_explode_m02(body, contact, normal)
		else:
			_ricochet_at(body, contact, normal)
		if consumed:
			break
		# Push outside the collider so one contact does not count twice.
		var separation: float = (hit_shape.shape as CircleShape2D).radius + 0.5
		global_position = contact + normal * separation
		travel_left = maxf(0.0, travel_left - separation)


func _ricochet_at(body: Node2D, contact: Vector2, normal: Vector2) -> void:
	visual_impact.emit(contact, mode)
	var incoming: Vector2 = direction
	if _valid_enemy(body):
		var enemy_id: int = body.get_instance_id()
		if card_attack.primary_hit_ids.has(enemy_id):
			card_attack.apply_secondary_hit(body, damage, incoming, combat_effects)
		else:
			card_attack.apply_primary_hit(body, contact, incoming, combat_effects)
	_show_slime_impact(normal)
	if remaining_ricochets <= 0:
		consumed = true
		phase = &"impact_ending"
		global_position = contact
		return
	remaining_ricochets -= 1
	direction = incoming.bounce(normal).normalized()
	if not _valid_enemy(body) and not wall_speed_boost_applied:
		speed *= wall_bounce_speed_multiplier
		wall_speed_boost_applied = true


func _explode_m02(body: Node2D, contact: Vector2, normal: Vector2) -> void:
	if consumed:
		return
	visual_impact.emit(contact, mode)
	consumed = true
	phase = &"impact_ending"
	global_position = contact
	_show_slime_impact(normal)
	slime_impact_time = 0.12
	visual.scale = Vector2.ONE * 1.5
	set_deferred(&"monitoring", false)
	var primary: Node2D = body if _valid_enemy(body) else null
	if primary != null:
		card_attack.apply_primary_hit(primary, contact, direction, combat_effects)
	for candidate: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = candidate as Node2D
		if enemy == primary or not _valid_enemy(enemy):
			continue
		if enemy.global_position.distance_to(contact) > m02_blast_radius:
			continue
		var outward: Vector2 = contact.direction_to(enemy.global_position)
		if outward.is_zero_approx():
			outward = direction
		if primary == null:
			primary = enemy
			card_attack.apply_primary_hit(enemy, contact, outward, combat_effects)
		else:
			combat_effects.apply_hit(enemy, damage, outward, card_attack.impact_impulse, card_attack.on_weapon_kill)


func _show_slime_impact(normal: Vector2) -> void:
	slime_impact_time = SLIME_IMPACT_DURATION
	# Directional impact art is authored in world axes, not the bullet's rotation.
	rotation = 0.0
	visual.flip_v = false
	if absf(normal.x) > absf(normal.y):
		visual.texture = M01_IMPACT_LEFT if normal.x < 0.0 else M01_IMPACT_RIGHT
		if mode == &"M02":
			visual.texture = M02_IMPACT_LEFT if normal.x < 0.0 else M02_IMPACT_RIGHT
	else:
		visual.texture = M02_IMPACT_UPDOWN if mode == &"M02" else M01_IMPACT_UPDOWN
		visual.flip_v = normal.y > 0.0


func _on_body_entered(body: Node2D) -> void:
	# The swept slime ray owns the contact; this signal has no surface normal.
	if mode == &"M01" or mode == &"M02":
		return
	if consumed or is_queued_for_deletion() or phase != &"flying" or not _valid_enemy(body):
		return
	var enemy_id: int = body.get_instance_id()
	if hit_ids.has(enemy_id):
		return
	hit_ids[enemy_id] = true
	if mode == &"M05":
		_explode_mushroom(body)
		return
	card_attack.apply_primary_hit(body, global_position, direction, combat_effects)
	visual_impact.emit(global_position, mode)
	if mode == &"M06":
		target = body
		attached_offset = global_position - body.global_position
		phase = &"attached"
		attached_time = 1.2
		tick_timer = 0.32
		tick_damage = 1.0
		set_deferred(&"monitoring", false)
	else:
		consumed = true
		hide()
		queue_free()


func _update_attached(delta: float) -> void:
	if not _valid_enemy(target):
		queue_free()
		return
	global_position = target.global_position + attached_offset
	visual.texture = frames[int(animation_clock * frame_rate) % frames.size()]
	attached_time -= delta
	tick_timer -= delta
	if attached_time > 0.0:
		while tick_timer <= 0.0:
			card_attack.apply_secondary_hit(target, tick_damage, direction, combat_effects)
			tick_timer += 0.32
		return
	queue_free()


func _explode_mushroom(primary: Node2D) -> void:
	if phase == &"burst":
		return
	phase = &"burst"
	set_deferred(&"monitoring", false)
	frames = M05_BOOM
	animation_clock = 0.0
	lifetime = float(frames.size()) / 30.0
	visual.scale = Vector2.ONE * 0.75
	visual.texture = frames[0]
	rotation = 0.0
	var center: Vector2 = global_position
	visual_impact.emit(center, mode)
	card_attack.apply_primary_hit(primary, center, direction, combat_effects)
	for candidate: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = candidate as Node2D
		if enemy == primary or not _valid_enemy(enemy):
			continue
		if enemy.global_position.distance_to(center) <= 22.0:
			card_attack.apply_secondary_hit(enemy, damage, center.direction_to(enemy.global_position), combat_effects)


func _nearest_enemy() -> Node2D:
	var closest: Node2D = null
	var best_distance: float = 260.0 * 260.0
	for candidate: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = candidate as Node2D
		if not _valid_enemy(enemy):
			continue
		var distance: float = global_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			closest = enemy
	return closest


func _valid_enemy(enemy: Node2D) -> bool:
	return is_instance_valid(enemy) and enemy.is_in_group(&"enemy_bodies") and enemy.has_method(&"is_alive") and bool(enemy.call(&"is_alive"))
