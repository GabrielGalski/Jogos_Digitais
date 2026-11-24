class_name MutationCard
extends CardDefinition
## One equipped passive reaction or F-activated ability, with caster-local cooldowns.

@export_range(0.0, 2.0) var movement_bonus: float = 0.2
@export_range(0.01, 60.0) var duration: float = 3.0
const HERO_SWORD: int = 4
const ASH_STEP: int = 6
const PRIMORDIAL_CONVERGENCE: int = 7
const TWILIGHT_MANTLE: int = 8
const CRIMSON_PULSE: int = 9
const MIDNIGHT_PROCESSION: int = 10
const CRIMSON_WINGS: int = 11
const DRAGON_GREED: int = 12

@export_enum("Fury", "Medusa", "Carnivorous", "Mandrake", "HeroSword", "Doppelganger", "AshStep", "PrimordialConvergence", "TwilightMantle", "CrimsonPulse", "MidnightProcession", "CrimsonWings", "DragonGreed") var effect: int = 0
@export var cooldown: float = 0.0

func get_kind() -> Kind:
	return Kind.MUTATION

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if movement_bonus < 0.0 or duration <= 0.0:
		errors.append("Mutation needs a nonnegative bonus and a positive duration.")
	return errors
