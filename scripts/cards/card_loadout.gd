class_name CardLoadout
extends Resource
## One typed slot per class. Empty manifestation means no attack, not a fallback shot.

@export var manifestation: ManifestationCard
@export var infusion: InfusionCard
@export var mutation: MutationCard

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	for card: CardDefinition in [manifestation, infusion, mutation]:
		if card != null:
			errors.append_array(card.validation_errors())
	return errors
