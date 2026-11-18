extends RefCounted

const MANIFESTATIONS: Array[ProceduralManifestationModel] = [
	preload("res://resources/weapons/procedural/M01.tres"),
	preload("res://resources/weapons/procedural/M02.tres"),
	preload("res://resources/weapons/procedural/M04.tres"),
	preload("res://resources/weapons/procedural/M06.tres"),
	preload("res://resources/weapons/procedural/M07.tres"),
	preload("res://resources/weapons/procedural/M08.tres"),
]
const INFUSIONS: Array[InfusionCard] = [
	preload("res://resources/cards/golem_core.tres"),
	preload("res://resources/cards/infusions/I02.tres"),
	preload("res://resources/cards/infusions/I03.tres"),
	preload("res://resources/cards/infusions/I04.tres"),
	preload("res://resources/cards/infusions/I05.tres"),
]
const MUTATIONS: Array[MutationCard] = [
	preload("res://resources/cards/fury_heart.tres"),
	preload("res://resources/cards/mutations/U02.tres"),
	preload("res://resources/cards/mutations/U03.tres"),
	preload("res://resources/cards/mutations/U04.tres"),
	preload("res://resources/cards/mutations/U05.tres"),
	preload("res://resources/cards/mutations/U06.tres"),
]


static func implemented_cards() -> Array[CardDefinition]:
	var cards: Array[CardDefinition] = []
	for model: ProceduralManifestationModel in MANIFESTATIONS:
		cards.append(model.card)
	cards.append_array(INFUSIONS)
	cards.append_array(MUTATIONS)
	return cards


static func art_paths() -> Dictionary[StringName, String]:
	var paths: Dictionary[StringName, String] = {}
	for aspect: String in ["manifestacao", "infusao", "mutacao"]:
		var folder: String = "res://assets/cards/" + aspect
		for directory: String in DirAccess.get_directories_at(folder):
			var path: String = folder + "/" + directory + "/" + directory + ".png"
			if ResourceLoader.exists(path):
				paths[StringName(directory.get_slice(" ", 1))] = path
	return paths


static func art_bounds() -> Rect2:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/card_art_layout.json")) as Dictionary
	var bounds: Array = layout["visible_rect"] as Array
	return Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3]))


static func alias(card: CardDefinition) -> StringName:
	if card == null:
		return &""
	if card.get_kind() == CardDefinition.Kind.INFUSION:
		return StringName("I%02d" % ((card as InfusionCard).effect + 1))
	if card.get_kind() == CardDefinition.Kind.MUTATION:
		return StringName("U%02d" % ((card as MutationCard).effect + 1))
	return card.card_id
