class_name CardCombatRuntime
extends RefCounted
## Per-caster state. Loading a resource never shares timers between players.

var _loadout: CardLoadout
var mutation_generation: int = 0
var mutation_remaining: float = 0.0
var effect_host: WeakRef
var infusion_generation: int = 0
var chimera_phase: int = 0
var cooldowns: Dictionary[StringName, float] = {}
var crimson_charge: int = 0
var dragon_kills: int = 0

func equip(loadout: CardLoadout) -> bool:
	if loadout == null or not loadout.validation_errors().is_empty():
		return false
	var old_infusion: StringName = _loadout.infusion.card_id if _loadout != null and _loadout.infusion != null else &""
	var old_mutation: StringName = _loadout.mutation.card_id if _loadout != null and _loadout.mutation != null else &""
	_loadout = loadout.duplicate(true) as CardLoadout
	if old_infusion != (_loadout.infusion.card_id if _loadout.infusion != null else &""):
		infusion_generation += 1
	if old_mutation != (_loadout.mutation.card_id if _loadout.mutation != null else &""):
		mutation_generation += 1
		mutation_remaining = 0.0
	return true

func reset_effects() -> void:
	mutation_generation += 1
	mutation_remaining = 0.0
	crimson_charge = 0
	cooldowns.clear()

func tick(delta: float) -> void:
	mutation_remaining = maxf(0.0, mutation_remaining - maxf(0.0, delta))
	for id: StringName in cooldowns:
		cooldowns[id] = maxf(0.0, cooldowns[id] - maxf(0.0, delta))

func movement_multiplier() -> float:
	if _loadout == null or _loadout.mutation == null or _loadout.mutation.effect != 0 or mutation_remaining <= 0.0:
		return 1.0
	return 1.0 + _loadout.mutation.movement_bonus

func create_attack() -> CardAttack:
	if _loadout == null or _loadout.manifestation == null:
		return null
	var card: ManifestationCard = _loadout.manifestation
	var attack: CardAttack = CardAttack.new()
	attack.manifestation_id = card.card_id
	attack.damage = card.damage
	attack.fire_interval = card.fire_interval
	attack.projectile_speed = card.projectile_speed
	attack.projectile_lifetime = card.projectile_lifetime
	attack.impact_impulse = card.impact_impulse
	attack.on_weapon_kill = _on_weapon_kill.bind(mutation_generation)
	attack.runtime = self
	attack.infusion_generation = infusion_generation
	attack.mutation_generation = mutation_generation
	if _loadout.infusion != null:
		attack.infusion_effect = _loadout.infusion.effect
		attack.infusion_cooldown = _loadout.infusion.cooldown
		attack.explosion_radius = _loadout.infusion.explosion_radius
		if attack.infusion_effect == 3 and float(cooldowns.get(&"I04", 0.0)) <= 0.0:
			attack.slaad_carrier = true
			cooldowns[&"I04"] = _loadout.infusion.cooldown
		if attack.infusion_effect == 4:
			attack.element = chimera_phase
			chimera_phase = (chimera_phase + 1) % 3
	return attack


func host() -> Node:
	return effect_host.get_ref() as Node if effect_host != null else null


func mutation_effect() -> int:
	return _loadout.mutation.effect if _loadout != null and _loadout.mutation != null else -1


func infusion_effect() -> int:
	return _loadout.infusion.effect if _loadout != null and _loadout.infusion != null else -1


func infusion_cooldown() -> float:
	return _loadout.infusion.cooldown if _loadout != null and _loadout.infusion != null else 0.0


func manifestation_id() -> StringName:
	return _loadout.manifestation.card_id if _loadout != null and _loadout.manifestation != null else &""


func copy_loadout() -> CardLoadout:
	return _loadout.duplicate(true) as CardLoadout if _loadout != null else null

func _on_weapon_kill(generation: int) -> void:
	# A projectile from an earlier loadout cannot activate the newly equipped mutation.
	if generation == mutation_generation and _loadout != null and _loadout.mutation != null and _loadout.mutation.effect == 0:
		mutation_remaining = _loadout.mutation.duration
