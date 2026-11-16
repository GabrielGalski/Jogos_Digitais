extends Node2D
## Binds each LDtk totem to its authored encounter and terrain surface.
const PEDESTAL: Script = preload("res://scripts/dungeon/horde_pedestal.gd")
const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
var pedestals: Array[Node2D] = []


static func support_regions(layers: Array, size_multiplier: float = 1.0) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) == "HordePedestal" and bool(ENTITIES.fields(entity).get("Enabled", true)):
				var region: Rect2 = ENTITIES.entity_rect(entity, offset)
				# Keep the original walkable support independently of the editor sprite.
				var scaled_size: Vector2 = Vector2(64, 64) * maxf(size_multiplier, 0.01)
				result.append(Rect2(region.get_center() - scaled_size * 0.5, scaled_size))
	return result


func build(layers: Array, player: Player, encounters: Array, terrain_height: Callable) -> void:
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "HordePedestal":
				continue
			var config: Dictionary = ENTITIES.fields(entity)
			if not bool(config.get("Enabled", true)):
				continue
			var footprint: Rect2 = ENTITIES.entity_rect(entity, offset)
			config["position"] = footprint.get_center()
			config["TerrainHeight"] = terrain_height.call(to_global(footprint.get_center()))
			config["BodyWidth"] = footprint.size.x * 0.792
			var pedestal: Node2D = PEDESTAL.new() as Node2D
			pedestal.name = "Pedestal_%d" % pedestals.size()
			add_child(pedestal)
			pedestal.call("configure", config)
			for encounter: Node2D in encounters:
				if str(encounter.get("encounter_id")) == str(config.get("EncounterId", "spirit_horde_1")):
					pedestal.call("bind_encounter", player, encounter)
					break
			pedestals.append(pedestal)
	player.bind_floor_height(terrain_height)
