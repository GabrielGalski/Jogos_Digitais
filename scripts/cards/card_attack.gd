class_name CardAttack
extends RefCounted
## Per-emission numerical snapshot. Never reads the currently equipped cards.

var damage: float
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

func resolve_hit(target: Node2D, position: Vector2, direction: Vector2, effects: CombatEffects) -> void:
	if resolved:
		return
	resolved = true
	apply_primary_hit(target, position, direction, effects)


func apply_primary_hit(target: Node2D, hit_position: Vector2, direction: Vector2, effects: CombatEffects) -> void:
	if not is_instance_valid(target) or not is_instance_valid(effects):
		return
	if target.is_queued_for_deletion() or not target.has_method(&"is_alive") or not bool(target.call(&"is_alive")):
		return
	var target_id: int = target.get_instance_id()
	if primary_hit_ids.has(target_id):
		return
	primary_hit_ids[target_id] = true
	effects.apply_hit(target, damage, direction, impact_impulse, on_weapon_kill)
	if not infusion_triggered:
		infusion_triggered = true
		if explosion_damage > 0.0 and explosion_radius > 0.0:
			effects.trigger_explosion(hit_position, explosion_radius, explosion_damage, on_weapon_kill)


func apply_secondary_hit(target: Node2D, amount: float, direction: Vector2, effects: CombatEffects) -> void:
	# Ticks and native area damage keep kill attribution without retriggering infusion.
	if is_instance_valid(effects):
		effects.apply_hit(target, amount, direction, 0.0, on_weapon_kill)
