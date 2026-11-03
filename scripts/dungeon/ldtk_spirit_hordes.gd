extends Node2D
## LDtk adapter: authored utility areas create isolated reusable encounters.
const ENCOUNTER: Script = preload("res://scripts/dungeon/spirit_horde_encounter.gd")
const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
var encounters: Array[Node2D] = []


func build(layers: Array, player: Player, gameplay: Node2D, floor_query: Callable, remains: Node2D = null, height_query: Callable = Callable(), allowed_arena_cells: Dictionary = {}) -> void:
	y_sort_enabled = true
	var pedestal_centers: Dictionary[String, Vector2] = {}
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)): continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "HordePedestal": continue
			var config: Dictionary = ENTITIES.fields(entity)
			if bool(config.get("Enabled", true)):
				pedestal_centers[str(config.get("EncounterId", ""))] = ENTITIES.entity_rect(entity, offset).get_center()
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			var kind: String = str(entity.get("__identifier", ""))
			if kind not in ["SpiritHordeArea", "PedestalArena"]:
				continue
			var config: Dictionary = ENTITIES.fields(entity)
			if not bool(config.get("Enabled", true)):
				continue
			var bounds: Rect2 = ENTITIES.entity_rect(entity, offset)
			if kind == "PedestalArena":
				config["ActivateOnEnter"] = false
				var requested_radius: Variant = config.get("RadiusPx", null)
				config["ArenaRadius"] = maxf(float(requested_radius) if requested_radius is int or requested_radius is float else minf(bounds.size.x, bounds.size.y) * 0.5, 64.0)
				config["ArenaCenter"] = pedestal_centers.get(str(config.get("EncounterId", "")), bounds.get_center())
				config["AllowedArenaCells"] = allowed_arena_cells
				bounds = Rect2((config.ArenaCenter as Vector2) - Vector2.ONE * float(config.ArenaRadius), Vector2.ONE * float(config.ArenaRadius) * 2.0)
				config["ClearCondition"] = str(config.get("EncounterId", "")) + "_clear"
				config["EntryCondition"] = str(config.get("EncounterId", "")) + "_entry_open"
			var encounter: Node2D = ENCOUNTER.new() as Node2D
			encounter.name = "Encounter_%d" % encounters.size()
			encounter.y_sort_enabled = true
			add_child(encounter)
			encounter.call("configure", config, bounds, player, gameplay, floor_query, remains, height_query)
			encounters.append(encounter)
