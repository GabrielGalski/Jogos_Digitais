extends Node2D
## Authored elevation of terrain, independent of pedestal relief and map collisions.

const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
var areas: Array[Dictionary] = []
var ramps: Array[Dictionary] = []


func configure(layers: Array) -> void:
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			var kind: String = str(entity.get("__identifier", ""))
			if kind not in ["ElevationArea", "ElevationRamp"]:
				continue
			var config: Dictionary = ENTITIES.fields(entity)
			if not bool(config.get("Enabled", true)):
				continue
			var entry: Dictionary = {"rect": ENTITIES.entity_rect(entity, offset), "height": maxf(0.0, float(config.get("HeightPx", 24)))}
			if kind == "ElevationRamp":
				entry["direction"] = str(config.get("Direction", "North"))
				ramps.append(entry)
			else:
				areas.append(entry)


func height_at(world_point: Vector2) -> float:
	var point: Vector2 = to_local(world_point)
	for ramp: Dictionary in ramps:
		var rect: Rect2 = ramp.rect as Rect2
		if not rect.has_point(point):
			continue
		var fraction: Vector2 = (point - rect.position) / rect.size
		var progress: float = 1.0 - fraction.y
		match str(ramp.direction):
			"South": progress = fraction.y
			"East": progress = fraction.x
			"West": progress = 1.0 - fraction.x
		return clampf(progress, 0.0, 1.0) * float(ramp.height)
	var result: float = 0.0
	for area: Dictionary in areas:
		if (area.rect as Rect2).has_point(point):
			result = maxf(result, float(area.height))
	return result
