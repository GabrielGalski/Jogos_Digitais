class_name CardCombatRuntime
extends RefCounted
## Per-caster state. Loading a resource never shares timers between players.

var _loadout: CardLoadout
var _generation: int = 0
var mutation_remaining: float = 0.0

func equip(loadout: CardLoadout) -> bool:
	if loadout == null or not loadout.validation_errors().is_empty():
		return false
	_loadout = loadout.duplicate(true) as CardLoadout
	reset_effects()
	return true

func reset_effects() -> void:
	_generation += 1
	mutation_remaining = 0.0

func tick(delta: float) -> void:
	mutation_remaining = maxf(0.0, mutation_remaining - maxf(0.0, delta))

func movement_multiplier() -> float:
	if _loadout == null or _loadout.mutation == null or mutation_remaining <= 0.0:
		return 1.0
	return 1.0 + _loadout.mutation.movement_bonus

func create_attack() -> CardAttack:
	if _loadout == null or _loadout.manifestation == null:
		return null
	var card: ManifestationCard = _loadout.manifestation
	var attack: CardAttack = CardAttack.new()
	attack.damage = card.damage
	attack.fire_interval = card.fire_interval
	attack.projectile_speed = card.projectile_speed
	attack.projectile_lifetime = card.projectile_lifetime
	attack.impact_impulse = card.impact_impulse
	attack.on_weapon_kill = _on_weapon_kill.bind(_generation)
	if _loadout.infusion != null:
		attack.explosion_damage = _loadout.infusion.explosion_damage
		attack.explosion_radius = _loadout.infusion.explosion_radius
	return attack

func _on_weapon_kill(generation: int) -> void:
	# A projectile from an earlier loadout cannot activate the newly equipped mutation.
	if generation == _generation and _loadout != null and _loadout.mutation != null:
		mutation_remaining = _loadout.mutation.duration
