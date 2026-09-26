class_name CardDefinition
extends Resource
## Shared authored data. Combat state belongs to CardCombatRuntime, never this resource.

enum Kind { MANIFESTATION, INFUSION, MUTATION }
enum Rarity { COMMON, UNCOMMON, RARE }

@export var card_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var rarity: Rarity = Rarity.COMMON

func get_kind() -> Kind:
	return Kind.MANIFESTATION

func validation_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if card_id.is_empty() or display_name.strip_edges().is_empty():
		errors.append("A card needs a stable ID and a display name.")
	return errors
