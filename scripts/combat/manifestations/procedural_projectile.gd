extends Node2D
## Projectile executor. Contacts, native blast and attached DOT do not depend on art.

signal impacted(at: Vector2, model: ProceduralManifestationModel, radius: float, direction: Vector2)
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const VISUAL: Script = preload("res://scripts/visual/weapons/procedural_projectile_visual.gd")

var model: ProceduralManifestationModel
var attack: CardAttack
var effects: CombatEffects
var shooter: CollisionObject2D
var direction: Vector2 = Vector2.RIGHT
var remaining: float = 0.0
var phase: StringName = &"flying"
var target: Node2D = null
var attached_offset: Vector2 = Vector2.ZERO
var tick_remaining: float = 0.0
var visual: Node2D = null
var finished: bool = false
var mode: StringName = &""


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
	mode = model.code()
	visual = VISUAL.new() as Node2D
	visual.name = "ProceduralVisual"
	add_child(visual)
	visual.call("configure", model, factory, direction)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if finished or model == null:
		return
	remaining -= delta
	if phase == &"attached":
		_advance_attached(delta)
		return
	if remaining <= 0.0:
		_finish(false)
		return
	var endpoint: Vector2 = global_position + direction * attack.projectile_speed * delta
	var exclusions: Array[RID] = []
	if is_instance_valid(shooter):
		exclusions.append(shooter.get_rid())
	var contact: Dictionary = CONTACTS.sweep(get_tree(), get_world_2d().direct_space_state,
		global_position, endpoint, 5, model.hit_radius, exclusions)
	if contact.is_empty():
		global_position = endpoint
		return
	global_position = contact.get("position") as Vector2
	var body: Node2D = contact.get("collider") as Node2D
	if model.blast_radius > 0.0:
		_blast(body)
		_finish(true)
		return
	if _valid_enemy(body):
		attack.apply_primary_hit(body, global_position, direction, effects)
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
		if enemy.global_position.distance_to(global_position) > model.blast_radius:
			continue
		var outward: Vector2 = global_position.direction_to(enemy.global_position)
		if primary == null:
			primary = enemy
			attack.apply_primary_hit(enemy, global_position, outward, effects)
		else:
			attack.apply_secondary_hit(enemy, attack.damage, outward, effects)


func _advance_attached(delta: float) -> void:
	if not _valid_enemy(target):
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
		impacted.emit(global_position, model, maxf(model.blast_radius, 8.0), direction)
	queue_free()


func _valid_enemy(body: Node2D) -> bool:
	return is_instance_valid(body) and not body.is_queued_for_deletion() and body.is_in_group(&"enemy_bodies") and body.has_method("is_alive") and bool(body.call("is_alive"))
