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

func resolve_hit(target: Node2D, position: Vector2, direction: Vector2, effects: CombatEffects) -> void:
	if resolved:
		return
	resolved = true
	effects.apply_hit(target, damage, direction, impact_impulse, on_weapon_kill)
	if explosion_damage > 0.0 and explosion_radius > 0.0:
		effects.trigger_explosion(position, explosion_radius, explosion_damage, on_weapon_kill)
