extends SceneTree
## Composition ownership, failure paths, paired warp validation and legacy levels.

const COMPOSITION: Script = preload("res://scripts/dungeon/ldtk_level_composition.gd")
const WARPS: Script = preload("res://scripts/dungeon/ldtk_warps.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func fixture() -> Dictionary:
	var main_layers: Array = [
		{"__identifier": "Gameplay", "__type": "IntGrid", "__gridSize": 16, "intGridCsv": [0, 0]},
		{"__identifier": "GameplayAreas", "__type": "Entities", "__gridSize": 16, "entityInstances": [{"iid": "pedestal"}]},
		{"__identifier": "Floor", "__type": "Tiles", "__gridSize": 16, "gridTiles": []},
	]
	var art_layers: Array = [
		{"__identifier": "Gameplay", "__type": "IntGrid", "__gridSize": 16, "intGridCsv": [0, 0]},
		{"__identifier": "GameplayAreas", "__type": "Entities", "__gridSize": 16, "entityInstances": []},
		{"__identifier": "Floor", "__type": "Tiles", "__gridSize": 16, "gridTiles": [{"px": [16, 0], "src": [0, 0]}]},
	]
	return {"levels": [
		{"identifier": "Logic", "pxWid": 32, "pxHei": 16, "layerInstances": main_layers,
			"fieldInstances": [{"__identifier": "SceneryLevel", "__value": "Art"}]},
		{"identifier": "Art", "pxWid": 32, "pxHei": 16, "layerInstances": art_layers, "fieldInstances": []},
	]}


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var before: int = data.hash()
	var result: Dictionary = COMPOSITION.compose(data, "Room_2")
	check(bool(result.get("ok", false)), "Room_2 composes its scenery")
	check((result.get("source_levels") as PackedStringArray) == PackedStringArray(["Room_2", "Room_2_Cenario"]), "Composition identifies both authoring levels")
	var entity_count: int = 0
	var tile_count: int = 0
	var arena_count: int = 0
	var ambient_zone_count: int = 0
	var authored_spawn: Vector2 = Vector2.INF
	for layer: Dictionary in result.layers:
		entity_count += (layer.get("entityInstances", []) as Array).size()
		tile_count += (layer.get("gridTiles", []) as Array).size() + (layer.get("autoLayerTiles", []) as Array).size()
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) == "PedestalArena": arena_count += 1
			if str(entity.get("__identifier", "")) == "FlyingEyeZone": ambient_zone_count += 1
			if str(entity.get("__identifier", "")) == "Warp":
				for field: Dictionary in entity.fieldInstances:
					if str(field.__identifier) == "WarpId" and str(field.__value) == "room_2_center":
						authored_spawn = Vector2(float(entity.px[0]), float(entity.px[1]) - 10.0)
	check(entity_count == 19 + ambient_zone_count and ambient_zone_count == 20 and arena_count == 6 and tile_count > 40000, "Gameplay, ambient zones and all scenery tiles are loaded once")
	check(data.hash() == before, "Composition never mutates authored data")
	var legacy: Dictionary = COMPOSITION.compose(data, "Room_1")
	check(bool(legacy.get("ok", false)) and (legacy.source_levels as PackedStringArray).size() == 1, "Unpaired Room_1 keeps its original path")
	var route: Dictionary = WARPS.resolve("res://monster_booster.ldtk", {"TargetLevel": "Room_2", "TargetWarp": "room_2_center"})
	check(bool(route.get("ok", false)) and (route.get("spawn") as Vector2).is_equal_approx(authored_spawn), "Warp validation finds support at the authored entrance in the scenery level")
	var valid: Dictionary = fixture()
	var composed: Dictionary = COMPOSITION.compose(valid, "Logic")
	check(bool(composed.get("ok", false)), "Minimal paired fixture is valid")
	check((composed.layers as Array)[1].entityInstances.size() == 1 and (composed.layers as Array)[2].gridTiles.size() == 1, "Layer ownership combines logic and art once")
	var invalid: Dictionary = fixture()
	(invalid.levels as Array)[0].fieldInstances[0].__value = "Missing"
	check(not bool(COMPOSITION.compose(invalid, "Logic").ok), "Missing scenery is rejected")
	invalid = fixture()
	(invalid.levels as Array)[0].fieldInstances[0].__value = "Logic"
	check(not bool(COMPOSITION.compose(invalid, "Logic").ok), "Self reference is rejected")
	invalid = fixture()
	(invalid.levels as Array)[1].pxWid = 48
	check(not bool(COMPOSITION.compose(invalid, "Logic").ok), "Different map sizes are rejected")
	invalid = fixture()
	(invalid.levels as Array)[1].layerInstances[2].__gridSize = 8
	check(not bool(COMPOSITION.compose(invalid, "Logic").ok), "Different grids are rejected")
	invalid = fixture()
	(invalid.levels as Array)[1].layerInstances[1].entityInstances.append({"iid": "duplicate"})
	check(not bool(COMPOSITION.compose(invalid, "Logic").ok), "Gameplay entities in scenery are rejected")
	invalid = fixture()
	(invalid.levels as Array)[0].layerInstances[2].gridTiles.append({"px": [0, 0]})
	check(not bool(COMPOSITION.compose(invalid, "Logic").ok), "Tiles duplicated in gameplay are rejected")
	invalid = fixture()
	(invalid.levels as Array)[1].fieldInstances.append({"__identifier": "SceneryLevel", "__value": "Logic"})
	check(not bool(COMPOSITION.compose(invalid, "Logic").ok), "Cycles and chained scenery are rejected")
	print("LDTK_COMPOSITION_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)
