extends Node2D
## LDtk positions are the cabinet's feet; its art follows the local terrain.

const TRADER: PackedScene = preload("res://scenes/structures/card_trader.tscn")
const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")


func build(layers: Array, player: Player, terrain_height: Callable) -> void:
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "CardTrader":
				continue
			var config: Dictionary = ENTITIES.fields(entity)
			if not bool(config.get("Enabled", true)):
				continue
			var pixel: Array = entity.get("px", [0, 0]) as Array
			var point: Vector2 = Vector2(float(pixel[0]), float(pixel[1])) + offset
			config["position"] = point
			config["TerrainHeight"] = terrain_height.call(to_global(point))
			config["DisplayScale"] = minf(float(entity.get("width", 64)), float(entity.get("height", 64))) / 64.0
			var trader: Node2D = TRADER.instantiate() as Node2D
			trader.name = "CardTrader_" + str(get_child_count())
			add_child(trader)
			trader.call("configure", player, get_parent(), config)
