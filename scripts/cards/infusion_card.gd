class_name InfusionCard
extends CardDefinition
## Initial infusion: one explosion on the primary projectile's first enemy hit.
## Secondary damage never emits another infusion.

@export_range(0.01, 1000.0) var explosion_damage: float = 3.0
@export_range(0.01, 1000.0) var explosion_radius: float = 18.0

func get_kind() -> Kind:
	return Kind.INFUSION

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if explosion_damage <= 0.0 or explosion_radius <= 0.0:
		errors.append("Infusion damage and radius must be positive.")
	return errors
