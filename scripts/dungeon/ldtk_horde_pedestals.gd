extends Node2D
## LDtk pedestal adapter; combines local relief with the supplied ground query.
const PEDESTAL: Script = preload("res://scripts/dungeon/horde_pedestal.gd")
const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
var pedestals: Array[Node2D] = []
var _terrain_height: Callable = Callable()


static func support_regions(layers: Array) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) == "HordePedestal" and bool(ENTITIES.fields(entity).get("Enabled", true)):
				result.append(ENTITIES.entity_rect(entity, offset))
	return result


func build(layers: Array, textures: RefCounted, player: Player, encounters: Array, terrain_height: Callable = Callable()) -> void:
	_terrain_height = terrain_height
	var texture: Texture2D = textures.call("get_texture", "assets/tiles/floor/pedestal.png") as Texture2D
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
			config["position"] = ENTITIES.entity_rect(entity, offset).get_center()
			var pedestal: Node2D = PEDESTAL.new() as Node2D
			pedestal.name = "Pedestal_%d" % pedestals.size()
			pedestal.call("configure", config, texture)
			add_child(pedestal)
			if _terrain_height.is_valid():
				var base_height: float = float(_terrain_height.call(pedestal.global_position))
				for child: Node in pedestal.get_children():
					if child is Node2D:
						(child as Node2D).position.y -= base_height
			for encounter: Node2D in encounters:
				if str(encounter.get("encounter_id")) == str(config.get("EncounterId", "spirit_horde_1")):
					pedestal.call("bind_encounter", player, encounter)
					break
			pedestals.append(pedestal)
	player.bind_floor_height(height_at)


func height_at(world_feet: Vector2) -> float:
	var result: float = 0.0
	for pedestal: Node2D in pedestals:
		result = maxf(result, float(pedestal.call("height_at", world_feet)))
	return result + (float(_terrain_height.call(world_feet)) if _terrain_height.is_valid() else 0.0)
