class_name InfusionCard
extends CardDefinition
## One equipped weapon modifier. Execution and kill chains live in CardEffectController.

@export_range(0.01, 1000.0) var explosion_damage: float = 3.0
@export_range(0.01, 1000.0) var explosion_radius: float = 18.0
@export_enum("Golem", "Shards", "Odopi", "Slaad", "Chimera") var effect: int = 0
@export var cooldown: float = 0.0

func get_kind() -> Kind:
	return Kind.INFUSION

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if explosion_damage <= 0.0 or explosion_radius <= 0.0:
		errors.append("Infusion damage and radius must be positive.")
	return errors
