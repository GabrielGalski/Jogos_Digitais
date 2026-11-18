class_name MutationCard
extends CardDefinition
## One equipped passive reaction or F-activated ability, with caster-local cooldowns.

@export_range(0.0, 2.0) var movement_bonus: float = 0.2
@export_range(0.01, 60.0) var duration: float = 3.0
@export_enum("Fury", "Medusa", "Carnivorous", "Mandrake", "SlimeTrail", "Doppelganger") var effect: int = 0
@export var cooldown: float = 0.0

func get_kind() -> Kind:
	return Kind.MUTATION

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if movement_bonus < 0.0 or duration <= 0.0:
		errors.append("Mutation needs a nonnegative bonus and a positive duration.")
	return errors
