extends RefCounted
## Optional artistic overrides. Output contains world rectangles and normalized kinds.

const COAST: Script = preload("res://scripts/visual/water_coast.gd")


func descriptions_from_layers(layers: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "WaterShoreOverride":
				continue
			var fields: Dictionary = {}
			for field: Dictionary in entity.get("fieldInstances", []):
				fields[str(field.__identifier)] = field.__value
			if not bool(fields.get("Enabled", true)):
				continue
			var kind: int = COAST.kind_from_name(str(fields.get("CoastType", "Default")))
			if kind < 0:
				push_warning("Water shore: CoastType invalido em " + str(entity.get("iid", "")))
				continue
			var size: Vector2 = Vector2(float(entity.get("width", 16)), float(entity.get("height", 16)))
			var pixel: Array = entity.get("px", [0, 0])
			var pivot: Array = entity.get("__pivot", [0, 0])
			var at: Vector2 = Vector2(float(pixel[0]), float(pixel[1])) + offset - Vector2(float(pivot[0]), float(pivot[1])) * size
			result.append({"id": str(entity.get("iid", "")), "rect": Rect2(at, size), "kind": kind,
				"priority": int(fields.get("Priority", 0))})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.priority) < int(b.priority) if int(a.priority) != int(b.priority) else str(a.id) < str(b.id))
	return result
