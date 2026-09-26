class_name ManifestationCard
extends CardDefinition
## Initial manifestation: one directed projectile emitted by the caster.

@export_range(0.01, 1000.0) var damage: float = 3.0
@export_range(0.01, 10.0) var fire_interval: float = 0.18
@export_range(1.0, 2000.0) var projectile_speed: float = 180.0
@export_range(0.01, 30.0) var projectile_lifetime: float = 1.4
@export_range(0.0, 1000.0) var impact_impulse: float = 105.0

func get_kind() -> Kind:
	return Kind.MANIFESTATION

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if damage <= 0.0 or fire_interval <= 0.0 or projectile_speed <= 0.0 or projectile_lifetime <= 0.0 or impact_impulse < 0.0:
		errors.append("Manifestation combat values must be positive; impulse may be zero.")
	return errors
