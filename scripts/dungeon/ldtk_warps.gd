extends Node2D
## LDtk adapter, platform collection and read-only destination validation.

signal travel_requested(gate: Node2D)
const GATE: Script = preload("res://scripts/dungeon/warp_gate.gd")
const LEVEL_COMPOSITION: Script = preload("res://scripts/dungeon/ldtk_level_composition.gd")
var gates: Array[Node2D] = []


static func levels(data: Dictionary) -> Array:
	var result: Array = data.get("levels",[]).duplicate()
	for world: Dictionary in data.get("worlds",[]):
		result.append_array(world.get("levels",[]))
	return result


static func descriptions(layers: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for layer: Dictionary in layers:
		if not bool(layer.get("visible",true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX",0)),float(layer.get("__pxTotalOffsetY",0)))
		for entity: Dictionary in layer.get("entityInstances",[]):
			if str(entity.get("__identifier","")) != "Warp":
				continue
			var config: Dictionary = {"WarpId":"entry","TargetLevel":"","TargetWarp":"entry","TargetMap":"","IsEntrance":false,"Enabled":true}
			for field: Dictionary in entity.get("fieldInstances",[]):
				if field.get("__value") != null:
					config[str(field.get("__identifier",""))] = field["__value"]
			if not bool(config.Enabled):
				continue
			var pixel: Array = entity.get("px",[0,0])
			var pivot: Array = entity.get("__pivot",[0.5,0.5])
			config["position"] = Vector2(float(pixel[0]),float(pixel[1])) + offset + Vector2((0.5-float(pivot[0]))*float(entity.get("width",48)),(0.5-float(pivot[1]))*float(entity.get("height",48)))
			result.append(config)
	return result


func build(layers: Array, textures: RefCounted) -> void:
	var texture: Texture2D = textures.call("get_texture","assets/tiles/floor/warp.png") as Texture2D
	for config: Dictionary in descriptions(layers):
		var gate: Node2D = GATE.new() as Node2D
		gate.name = "Warp_" + str(gates.size())
		gate.call("configure",config,texture)
		add_child(gate)
		gate.connect("travel_requested",func(point: Node2D) -> void: travel_requested.emit(point))
		gates.append(gate)


func entrance(warp_id: String = "") -> Node2D:
	for gate: Node2D in gates:
		var config: Dictionary = gate.get("data")
		if (not warp_id.is_empty() and str(config.WarpId) == warp_id) or (warp_id.is_empty() and bool(config.IsEntrance)):
			return gate
	return null


func bind_actor(player: Player, gameplay: Node2D = null) -> void:
	for gate: Node2D in gates:
		gate.set("actor",player)
		gate.set("gameplay", gameplay)


static func resolve(current_map: String, config: Dictionary) -> Dictionary:
	var scene_path: String = str(config.get("TargetScene", "")).strip_edges()
	if not scene_path.is_empty():
		scene_path = scene_path.simplify_path()
		var project_root: String = ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/") + "/"
		var absolute_scene: String = ProjectSettings.globalize_path(scene_path).simplify_path()
		if not scene_path.begins_with("res://") or not absolute_scene.begins_with(project_root) or scene_path.get_extension().to_lower() != "tscn":
			return {"ok": false, "error": "Cena deve ser um .tscn dentro do projeto."}
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			return {"ok": false, "error": "Cena de destino nao encontrada."}
		return {"ok": true, "scene_path": scene_path}
	var path: String = str(config.get("TargetMap","")).strip_edges()
	if path.is_empty():
		path = current_map
	elif not path.begins_with("res://"):
		if path.is_absolute_path() or path.contains(":"):
			return {"ok":false,"error":"Mapa deve estar dentro do projeto."}
		path = current_map.get_base_dir().path_join(path)
	path = path.simplify_path()
	var root_path: String = ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/") + "/"
	var absolute: String = ProjectSettings.globalize_path(path).simplify_path()
	if not absolute.begins_with(root_path) or path.get_extension().to_lower() != "ldtk":
		return {"ok":false,"error":"Caminho de mapa invalido."}
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"error":"Mapa de destino nao encontrado."}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok":false,"error":"Mapa de destino invalido."}
	for level: Dictionary in levels(parsed):
		if str(level.get("identifier","")) != str(config.get("TargetLevel","")):
			continue
		if not level.get("layerInstances") is Array:
			return {"ok":false,"error":"Sala externa nao carregada."}
		var composition: Dictionary = LEVEL_COMPOSITION.compose(parsed, str(level.identifier))
		if not bool(composition.get("ok", false)):
			return {"ok": false, "error": str(composition.get("error", "Composicao de destino invalida."))}
		var destination_layers: Array = composition.layers as Array
		var matches: Array[Dictionary] = []
		for candidate: Dictionary in descriptions(destination_layers):
			if str(candidate.WarpId) == str(config.get("TargetWarp","entry")):
				matches.append(candidate)
		if matches.size() != 1:
			return {"ok":false,"error":"Warp de destino ausente ou com ID duplicado."}
		var spawn: Vector2 = (matches[0].position as Vector2) + Vector2(0,-10)
		for layer: Dictionary in destination_layers:
			if str(layer.get("__identifier","")) != "Gameplay":
				continue
			var grid: int = int(layer.get("__gridSize",16))
			var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX",0)),float(layer.get("__pxTotalOffsetY",0)))
			var cell: Vector2i = Vector2i(((spawn+Vector2(0,3)-offset)/grid).floor())
			var width: int = int(layer.get("__cWid",1))
			var values: Array = layer.get("intGridCsv",[])
			var index: int = cell.y*width+cell.x
			if cell.x >= 0 and cell.x < width and index >= 0 and index < values.size() and int(values[index]) in [1,2,3,6,7]:
				return {"ok":false,"error":"Warp de destino sobre vao ou bloqueio de gameplay."}
		var safe: bool = false
		for layer: Dictionary in destination_layers:
			var layer_name: String = str(layer.get("__identifier", ""))
			if (layer_name != "Floor" and not layer_name.begins_with("Floor_")) or not bool(layer.get("visible",true)):
				continue
			var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX",0)),float(layer.get("__pxTotalOffsetY",0)))
			for tile: Dictionary in layer.get("gridTiles",[]) + layer.get("autoLayerTiles",[]):
				var pixel: Array = tile.get("px",[0,0])
				if Rect2(Vector2(float(pixel[0]),float(pixel[1]))+offset,Vector2(16,16)).has_point(spawn+Vector2(0,3)):
					safe = true
		if not safe:
			return {"ok":false,"error":"Warp de destino precisa estar sobre o piso."}
		return {"ok":true,"map_path":path,"level_name":str(level.identifier),"arrival_warp":str(matches[0].WarpId),"spawn":spawn}
	return {"ok":false,"error":"Sala de destino nao encontrada."}
