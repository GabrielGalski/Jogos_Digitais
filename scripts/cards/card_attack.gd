class_name CardAttack
extends RefCounted
## Per-emission numerical snapshot. Never reads the currently equipped cards.

var damage: float
var manifestation_id: StringName = &""
var fire_interval: float
var projectile_speed: float
var projectile_lifetime: float
var impact_impulse: float
var explosion_damage: float = 0.0
var explosion_radius: float = 0.0
var on_weapon_kill: Callable
var resolved: bool = false
var infusion_triggered: bool = false
var primary_hit_ids: Dictionary = {}
var separate_projectile_hits: bool = false
var runtime: CardCombatRuntime
var infusion_effect: int = -1
var infusion_cooldown: float = 0.0
var infusion_generation: int = 0
var mutation_generation: int = 0
var element: int = -1
var slaad_carrier: bool = false
var _slaad_used: bool = false

func resolve_hit(target: Node2D, position: Vector2, direction: Vector2, effects: CombatEffects) -> void:
	if resolved:
		return
	resolved = true
	apply_primary_hit(target, position, direction, effects)


func slaad_available() -> bool:
	return slaad_carrier and not _slaad_used


func apply_primary_hit(target: Node2D, hit_position: Vector2, direction: Vector2, effects: CombatEffects,
		damage_scale: float = 1.0) -> void:
	if not is_instance_valid(target) or not is_instance_valid(effects):
		return
	if target.is_in_group(&"sound_fields") or target.is_in_group(&"controlled_monsters"):
		return
	if target.is_queued_for_deletion() or not target.has_method(&"is_alive") or not bool(target.call(&"is_alive")):
		return
	var target_id: int = target.get_instance_id()
	if not separate_projectile_hits:
		if primary_hit_ids.has(target_id):
			return
		primary_hit_ids[target_id] = true
	var final_damage: float = damage * damage_scale * (1.35 if element == 0 else 1.0)
	var confirmed: bool = _apply_damage(target, final_damage, direction, impact_impulse, effects, hit_position)
	var service: Node = runtime.host() if runtime != null else null
	if confirmed and is_instance_valid(service):
		service.call("weapon_hit", self, target if is_instance_valid(target) else null)
	if is_instance_valid(service) and is_instance_valid(target) and bool(target.call("is_alive")):
		if element == 1:
			service.call("poison", target, maxf(0.5, damage * 0.2), 3.0, self)
		elif element == 2 and target.has_method("receive_impact"):
			target.call("receive_impact", direction, maxf(120.0, impact_impulse * 1.5))
		if slaad_available():
			_slaad_used = bool(service.call("attach_slaad", target))
		if confirmed and infusion_effect == InfusionCard.FIRE:
			service.call("inflict_fire", target, self)
	if not infusion_triggered:
		infusion_triggered = true
		if explosion_damage > 0.0 and explosion_radius > 0.0:
			effects.trigger_explosion(hit_position, explosion_radius, explosion_damage, on_weapon_kill)


func apply_secondary_hit(target: Node2D, amount: float, direction: Vector2, effects: CombatEffects, cascade_depth: int = 0, impulse: float = 0.0) -> bool:
	# Derived hits keep their snapshot and kill credit; only explicit kill effects can chain.
	if is_instance_valid(target) and is_instance_valid(effects):
		var impact: Vector2 = effects.CONTACTS.damage_center(target)
		return _apply_damage(target, amount, direction, impulse, effects, impact, cascade_depth)
	return false


func _apply_damage(target: Node2D, amount: float, direction: Vector2, impulse: float, effects: CombatEffects, impact: Vector2, depth: int = 0) -> bool:
	var at: Vector2 = effects.CONTACTS.damage_center(target)
	var credited_amount: float = CombatEffects.damage_after_freeze(target, amount)
	return effects.apply_hit(target, amount, direction, impulse, func() -> void:
		if on_weapon_kill.is_valid():
			on_weapon_kill.call()
		var service: Node = runtime.host() if runtime != null else null
		if is_instance_valid(service):
			service.call("weapon_kill", self, at, impact, credited_amount, depth)
	)
