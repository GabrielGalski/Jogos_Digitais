extends Node2D
## Projectile executor. Contacts, native blast and attached DOT do not depend on art.

signal impacted(at: Vector2, model: ProceduralManifestationModel, radius: float, direction: Vector2)
signal split_reached(at: Vector2, direction: Vector2, lifetime: float)
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const VISUAL: Script = preload("res://scripts/visual/weapons/procedural_projectile_visual.gd")

var model: ProceduralManifestationModel
var attack: CardAttack
var effects: CombatEffects
var shooter: CollisionObject2D
var direction: Vector2 = Vector2.RIGHT
var remaining: float = 0.0
var turn_rate: float = 0.0
var phase: StringName = &"flying"
var target: Node2D = null
var attached_offset: Vector2 = Vector2.ZERO
var tick_remaining: float = 0.0
var visual: Node2D = null
var finished: bool = false
var mode: StringName = &""
var parasite_visual: Sprite2D
var _passed_enemies: Dictionary[int, bool] = {}
var _blast_resolved: bool = false
var _distance_before_split: float = INF
var _collision_radius: float
var _damage_scale: float = 1.0
var _homing_target: Node2D
var _homing_acquired: bool = false
var _wall_reflected: bool = false
var _flight_speed: float


func _ready() -> void:
	add_to_group(&"player_projectiles")
	add_to_group(&"manifestation_projectiles")
	process_physics_priority = 3
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func configure(definition: ProceduralManifestationModel, snapshot: CardAttack, combat: CombatEffects,
		caster: CollisionObject2D, aim: Vector2, factory: ProceduralWeaponSpriteFactory) -> void:
	model = definition
	attack = snapshot
	effects = combat
	shooter = caster
	direction = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT
	remaining = attack.projectile_lifetime
	_flight_speed = attack.projectile_speed
	_collision_radius = model.hit_radius
	if model.split_distance > 0.0:
		_distance_before_split = model.split_distance
	mode = model.code()
	visual = VISUAL.new() as Node2D
	visual.name = "ProceduralVisual"
	add_child(visual)
	visual.call("configure", model, factory, direction)
	if attack.element >= 0:
		visual.call("set_element", attack.element)
	if attack.slaad_available():
		parasite_visual = Sprite2D.new()
		parasite_visual.texture = preload("res://assets/cards/infusao/ovo_de_slaad I04/slaad/slad1.png")
		parasite_visual.position.y = -5.0
		parasite_visual.scale = Vector2.ONE * (0.38 if model.projectile_count > 1 else 0.65)
		parasite_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(parasite_visual)
	reset_physics_interpolation()


func configure_split_shard(lifetime: float) -> void:
	_distance_before_split = INF
	remaining = lifetime
	_collision_radius *= 0.7
	_damage_scale = 0.65
	visual.scale *= 0.7


func _physics_process(delta: float) -> void:
	if finished or model == null:
		return
	if parasite_visual != null:
		parasite_visual.visible = attack.slaad_available()
	remaining -= delta
	if phase == &"attached":
		_advance_attached(delta)
		return
	if remaining <= 0.0:
		_finish(false)
		return
	if not _wall_reflected and model.homing_range > 0.0:
		_steer_toward_enemy(delta)
	if not is_zero_approx(turn_rate):
		direction = direction.rotated(turn_rate * delta)
		visual.set("direction", direction)
	var travel: float = minf(_flight_speed * delta, _distance_before_split)
	var endpoint: Vector2 = global_position + direction * travel
	var exclusions: Array[RID] = []
	if is_instance_valid(shooter):
		exclusions.append(shooter.get_rid())
	# Continue through the unused portion of the same physics step after a hit.
	while not finished and not is_queued_for_deletion():
		var contact: Dictionary = CONTACTS.sweep(get_tree(), get_world_2d().direct_space_state,
			global_position, endpoint, 5, _collision_radius, exclusions, _passed_enemies)
		if contact.is_empty():
			global_position = endpoint
			_distance_before_split -= travel
			if _distance_before_split <= 0.0:
				split_reached.emit(global_position, direction, remaining)
				_finish(false)
			return
		global_position = contact.get("position") as Vector2
		var body: Node2D = contact.get("collider") as Node2D
		if model.pierces_enemies and not bool(contact.get("sound_block", false)) and _valid_enemy(body):
			_pierce(body)
			continue
		var unused: float = global_position.distance_to(endpoint)
		if not _valid_enemy(body) and _reflect_at_wall(contact):
			travel = unused * CONTACTS.WALL_RICOCHET_SPEED
			endpoint = global_position + direction * travel
			if travel > 0.01:
				continue
			return
		_impact(contact, body)
		return


func _reflect_at_wall(contact: Dictionary) -> bool:
	if _wall_reflected or attack.infusion_effect != InfusionCard.GARGOYLE:
		return false
	var reflected: Vector2 = CONTACTS.wall_reflection(contact, direction)
	if reflected.is_zero_approx():
		return false
	if is_instance_valid(effects):
		effects.notify_surface_hit(global_position, direction)
	impacted.emit(global_position, model, 5.0, reflected)
	_wall_reflected = true
	_distance_before_split = INF
	_flight_speed *= CONTACTS.WALL_RICOCHET_SPEED
	turn_rate = 0.0
	direction = reflected
	global_position += (contact.normal as Vector2) * 0.6
	visual.set("direction", direction)
	return true


func _steer_toward_enemy(delta: float) -> void:
	if not _homing_acquired:
		_homing_acquired = true
		var best: float = model.homing_range * model.homing_range
		var exclusions: Array[RID] = []
		if is_instance_valid(shooter):
			exclusions.append(shooter.get_rid())
		for candidate: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
			var enemy: Node2D = candidate as Node2D
			if not _valid_enemy(enemy):
				continue
			var point: Vector2 = CONTACTS.damage_center(enemy)
			var distance: float = global_position.distance_squared_to(point)
			if distance >= best:
				continue
			if CONTACTS.terrain_ray(get_tree(), get_world_2d().direct_space_state, global_position, point, 1, exclusions).is_empty():
				best = distance
				_homing_target = enemy
	if not is_instance_valid(_homing_target) or not _valid_enemy(_homing_target):
		return
	var toward: Vector2 = global_position.direction_to(CONTACTS.damage_center(_homing_target))
	if not toward.is_zero_approx():
		direction = direction.rotated(clampf(direction.angle_to(toward), -20.0 * delta, 20.0 * delta))
		visual.set("direction", direction)


func _pierce(body: Node2D) -> void:
	_passed_enemies[body.get_instance_id()] = true
	if model.blast_radius > 0.0 and not _blast_resolved:
		_blast_resolved = true
		_blast(body)
		impacted.emit(global_position, model, model.blast_radius, direction)
	else:
		attack.apply_primary_hit(body, global_position, direction, effects)
		impacted.emit(global_position, model, 8.0, direction)


func _impact(contact: Dictionary, body: Node2D) -> void:
	if bool(contact.get("sound_block", false)):
		if is_instance_valid(effects):
			effects.notify_surface_hit(global_position, direction)
		_finish(true)
		return
	if model.blast_radius > 0.0 and not _blast_resolved:
		_blast(body)
		_finish(true)
		return
	if _valid_enemy(body):
		attack.apply_primary_hit(body, global_position, direction, effects, _damage_scale)
		if model.attached_duration > 0.0 and _valid_enemy(body):
			target = body
			attached_offset = global_position - body.global_position
			phase = &"attached"
			remaining = model.attached_duration
			tick_remaining = model.dot_interval
			visual.set("attached", true)
			impacted.emit(global_position, model, 5.0, direction)
			return
	elif is_instance_valid(effects):
		effects.notify_surface_hit(global_position, direction)
	_finish(true)


func _blast(body: Node2D) -> void:
	var primary: Node2D = body if _valid_enemy(body) else null
	if primary != null:
		attack.apply_primary_hit(primary, global_position, direction, effects)
	for candidate: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = candidate as Node2D
		if enemy == primary or not _valid_enemy(enemy):
			continue
		var center: Vector2 = CONTACTS.damage_center(enemy)
		if center.distance_to(global_position) > model.blast_radius:
			continue
		if attack.infusion_effect == InfusionCard.GARGOYLE:
			if not CONTACTS.terrain_ray(get_tree(), get_world_2d().direct_space_state, global_position - direction * 0.6, center, 1).is_empty():
				continue
		_passed_enemies[enemy.get_instance_id()] = true
		var outward: Vector2 = global_position.direction_to(center)
		if primary == null:
			primary = enemy
			attack.apply_primary_hit(enemy, global_position, outward, effects)
		else:
			attack.apply_secondary_hit(enemy, attack.damage, outward, effects)


func _advance_attached(delta: float) -> void:
	if not is_instance_valid(target) or not _valid_enemy(target) or target.is_in_group(&"sound_fields"):
		_finish(false)
		return
	global_position = target.global_position + attached_offset
	tick_remaining -= delta
	while tick_remaining <= 0.0 and remaining > 0.0 and _valid_enemy(target):
		attack.apply_secondary_hit(target, model.dot_damage, direction, effects)
		tick_remaining += model.dot_interval
	if remaining <= 0.0:
		_finish(false)


func _finish(show_impact: bool) -> void:
	if finished:
		return
	finished = true
	if show_impact:
		impacted.emit(global_position, model, 8.0 if _blast_resolved else maxf(model.blast_radius, 8.0), direction)
	queue_free()


func _valid_enemy(body: Node2D) -> bool:
	return is_instance_valid(body) and not body.is_queued_for_deletion() and body.is_in_group(&"enemy_bodies") and not body.is_in_group(&"controlled_monsters") and body.has_method("is_alive") and bool(body.call("is_alive"))
