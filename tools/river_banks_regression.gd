extends "res://tools/castle_cliffs_regression.gd"
## Catalog baseline: stones retained; authored barriers and new contour coexist.

func _physics_checks() -> void:
	await super._physics_checks()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_FILE)) as Dictionary
	var scenery: Dictionary = _level(data, "Room_2_Cenario")
	check(str(_layer(scenery, "Floor").get("__tilesetRelPath", "")).ends_with("/ground_base.png"), "The generated rounded atlas has been reverted")
	check((_layer(scenery, "WaterBanks").get("gridTiles", []) as Array).is_empty(), "The removed stone painting stays removed")
	check(not arena.has_node("FloorBoundary/RoundedRiverShore"), "No retired curved physical outline is active")
	check(arena.has_node("Barriers"), "The user's barrier painting retains its dedicated physical adapter")
	check(arena.has_node("RiverContour") and arena.has_node("FloorBoundary/RiverBanks"), "The current river uses shared procedural shore geometry")
	check(not arena.has_node("LdtkLayers/RiverWaterPreview_0"), "The retired editor layer is no longer loaded")
