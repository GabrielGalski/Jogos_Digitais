extends RefCounted
## Compose one gameplay level and its optional scenery level in local coordinates.
## Only tile layers come from scenery; entities and IntGrid belong to gameplay.


static func levels(data: Dictionary) -> Array:
	var result: Array = data.get("levels", []).duplicate()
	for world: Dictionary in data.get("worlds", []):
		result.append_array(world.get("levels", []))
	return result


static func scenery_name(level: Dictionary) -> String:
	for field: Dictionary in level.get("fieldInstances", []):
		if str(field.get("__identifier", "")) == "SceneryLevel":
			return str(field.get("__value", "")).strip_edges()
	return ""


static func compose(data: Dictionary, primary_name: String) -> Dictionary:
	var primary: Dictionary = {}
	var scenery: Dictionary = {}
	var entries: Array = levels(data)
	for level: Dictionary in entries:
		if str(level.get("identifier", "")) == primary_name:
			primary = level
	if primary.is_empty() or not primary.get("layerInstances") is Array:
		return {"ok": false, "error": "Level principal ausente ou externo: " + primary_name}
	var companion_name: String = scenery_name(primary)
	if companion_name.is_empty():
		return {"ok": true, "primary": primary, "layers": primary.layerInstances,
			"source_levels": PackedStringArray([primary_name])}
	if companion_name == primary_name:
		return {"ok": false, "error": "SceneryLevel nao pode apontar para o proprio level: " + primary_name}
	for level: Dictionary in entries:
		if str(level.get("identifier", "")) == companion_name:
			scenery = level
	if scenery.is_empty() or not scenery.get("layerInstances") is Array:
		return {"ok": false, "error": "Level de cenario ausente ou externo: " + companion_name}
	if not scenery_name(scenery).is_empty():
		return {"ok": false, "error": "O cenario nao pode encadear outro SceneryLevel: " + companion_name}
	if int(primary.pxWid) != int(scenery.pxWid) or int(primary.pxHei) != int(scenery.pxHei):
		return {"ok": false, "error": "Gameplay e cenario precisam ter o mesmo tamanho: " + primary_name + " / " + companion_name}
	var art: Dictionary[String, Dictionary] = {}
	for layer: Dictionary in scenery.layerInstances:
		var kind: String = str(layer.get("__type", ""))
		if kind in ["Tiles", "AutoLayer"]:
			art[str(layer.__identifier)] = layer
		elif _has_content(layer):
			return {"ok": false, "error": "Mova entidades e IntGrid para " + primary_name + ": " + str(layer.__identifier)}
	var combined: Array = []
	for layer: Dictionary in primary.layerInstances:
		var kind: String = str(layer.get("__type", ""))
		var layer_name: String = str(layer.get("__identifier", ""))
		if kind not in ["Tiles", "AutoLayer"]:
			combined.append(layer)
			continue
		if _has_content(layer):
			return {"ok": false, "error": "Mova os tiles para " + companion_name + ": " + layer_name}
		if not art.has(layer_name):
			return {"ok": false, "error": "Camada de tiles ausente no cenario: " + layer_name}
		var source: Dictionary = art[layer_name]
		if int(source.get("__gridSize", 0)) != int(layer.get("__gridSize", 0)):
			return {"ok": false, "error": "Grades divergentes entre os levels: " + layer_name}
		combined.append(source)
		art.erase(layer_name)
	if not art.is_empty():
		return {"ok": false, "error": "O cenario possui camadas sem par no gameplay: " + ", ".join(art.keys())}
	return {"ok": true, "primary": primary, "layers": combined,
		"source_levels": PackedStringArray([primary_name, companion_name])}


static func _has_content(layer: Dictionary) -> bool:
	if not (layer.get("entityInstances", []) as Array).is_empty():
		return true
	if not (layer.get("gridTiles", []) as Array).is_empty() or not (layer.get("autoLayerTiles", []) as Array).is_empty():
		return true
	for value: Variant in layer.get("intGridCsv", []):
		if int(value) != 0:
			return true
	return false
