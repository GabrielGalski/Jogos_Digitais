extends RefCounted
## LDtk adapter only. Coordinates remain local to the level's Godot root.

const DEFAULTS: Dictionary = {"Preset": "Lake", "MaskId": "Rectangle", "SurfaceId": "", "Enabled": true, "ClipToTerrain": false}


func descriptions_from_layers(layers: Array) -> Array[Dictionary]:
	var descriptions: Array[Dictionary] = []
	for layer: Dictionary in layers:
		if str(layer.get("__type", "")) != "Entities" or not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "WaterArea":
				continue
			var config: Dictionary = DEFAULTS.duplicate()
			for field: Dictionary in entity.get("fieldInstances", []):
				var value: Variant = field.get("__value")
				if value != null:
					config[str(field.get("__identifier", ""))] = value
			if not bool(config.Enabled):
				continue
			var pixel: Array = entity.get("px", [0, 0])
			var pivot: Array = entity.get("__pivot", [0, 0])
			var size: Vector2 = Vector2(float(entity.get("width", 16)), float(entity.get("height", 16)))
			if pixel.size() < 2 or pivot.size() < 2:
				continue
			var top_left: Vector2 = Vector2(float(pixel[0]), float(pixel[1])) + offset - size * Vector2(float(pivot[0]), float(pivot[1]))
			descriptions.append({"id": str(entity.get("iid", "water_%d" % descriptions.size())),
				"rect": Rect2(top_left, size), "preset": str(config.Preset),
				"mask_id": str(config.MaskId), "surface_id": str(config.SurfaceId),
				"clip_to_terrain": bool(config.ClipToTerrain)})
	return descriptions
