class_name InfusionCard
extends CardDefinition
## One equipped weapon modifier. Execution and kill chains live in CardEffectController.
const GOLEM: int = 0
const LIGHTNING: int = 5
const FIRE: int = 6
const ICE: int = 7
const CRYPT_THIRST: int = 8
const EXECUTIONER_MARK: int = 9
const GARGOYLE: int = 10
const DRAGON_METEOR: int = 11
const EMBER_HEAT: int = 12

@export_range(0.01, 1000.0) var explosion_damage: float = 3.0
@export_range(0.01, 1000.0) var explosion_radius: float = 18.0
@export_enum("Golem", "Shards", "Odopi", "Slaad", "Chimera", "Lightning", "Fire", "Ice", "CryptThirst", "ExecutionerMark", "Gargoyle", "DragonMeteor", "EmberHeat") var effect: int = 0
@export var cooldown: float = 0.0

func get_kind() -> Kind:
	return Kind.INFUSION

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = super.validation_errors()
	if explosion_damage <= 0.0 or explosion_radius <= 0.0:
		errors.append("Infusion damage and radius must be positive.")
	return errors
