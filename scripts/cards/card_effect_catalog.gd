extends RefCounted

const DRAGON_PACK: int = 4
const PACK_CODES: Array = [
	[&"M01", &"I01", &"U01", &"M02", &"I03", &"U06"],
	[&"M05", &"I02", &"U02", &"M06", &"I04", &"U05"],
	[&"M07", &"U03", &"U04", &"M04", &"I05", &"I11"],
	[&"M11", &"U12", &"I12", &"I13", &"U13", &"M08"],
]

const MANIFESTATIONS: Array[ProceduralManifestationModel] = [
	preload("res://resources/weapons/procedural/M01.tres"),
	preload("res://resources/weapons/procedural/M02.tres"),
	preload("res://resources/weapons/procedural/M04.tres"),
	preload("res://resources/weapons/procedural/M06.tres"),
	preload("res://resources/weapons/procedural/M07.tres"),
	preload("res://resources/weapons/procedural/M08.tres"),
	preload("res://resources/weapons/procedural/M05.tres"),
	preload("res://resources/weapons/procedural/M09.tres"),
	preload("res://resources/weapons/procedural/M10.tres"),
	preload("res://resources/weapons/procedural/M11.tres"),
]
const INFUSIONS: Array[InfusionCard] = [
	preload("res://resources/cards/golem_core.tres"),
	preload("res://resources/cards/infusions/I02.tres"),
	preload("res://resources/cards/infusions/I03.tres"),
	preload("res://resources/cards/infusions/I04.tres"),
	preload("res://resources/cards/infusions/I05.tres"),
	preload("res://resources/cards/infusions/I06.tres"),
	preload("res://resources/cards/infusions/I07.tres"),
	preload("res://resources/cards/infusions/I08.tres"),
	preload("res://resources/cards/infusions/I09.tres"),
	preload("res://resources/cards/infusions/I10.tres"),
	preload("res://resources/cards/infusions/I11.tres"),
	preload("res://resources/cards/infusions/I12.tres"),
	preload("res://resources/cards/infusions/I13.tres"),
]
const MUTATIONS: Array[MutationCard] = [
	preload("res://resources/cards/fury_heart.tres"),
	preload("res://resources/cards/mutations/U02.tres"),
	preload("res://resources/cards/mutations/U03.tres"),
	preload("res://resources/cards/mutations/U04.tres"),
	preload("res://resources/cards/mutations/U05.tres"),
	preload("res://resources/cards/mutations/U06.tres"),
	preload("res://resources/cards/mutations/U07.tres"),
	preload("res://resources/cards/mutations/U08.tres"),
	preload("res://resources/cards/mutations/U09.tres"),
	preload("res://resources/cards/mutations/U10.tres"),
	preload("res://resources/cards/mutations/U11.tres"),
	preload("res://resources/cards/mutations/U12.tres"),
	preload("res://resources/cards/mutations/U13.tres"),
]


static func draw_pack(volume: int) -> Array[CardDefinition]:
	var cards: Array[CardDefinition] = []
	for card: CardDefinition in implemented_cards():
		if alias(card) in PACK_CODES[volume - 1]:
			cards.append(card)
	cards.shuffle()
	return cards.slice(0, 3)


static func draw_horde_pack(volume: int) -> Array[CardDefinition]:
	var cards: Array[CardDefinition] = []
	for card: CardDefinition in implemented_cards():
		var code: StringName = alias(card)
		if code not in PACK_CODES[DRAGON_PACK - 1] and (code != &"I11" or volume == 3):
			cards.append(card)
	cards.shuffle()
	return cards.slice(0, 3)


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
