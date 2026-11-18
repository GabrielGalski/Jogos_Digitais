extends SceneTree

const GAMEPLAY: Script = preload("res://scripts/dungeon/ldtk_gameplay.gd")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("LDTK CLEANUP FAIL: " + message)


func _run() -> void:
	var gameplay: Node2D = GAMEPLAY.new() as Node2D
	root.add_child(gameplay)
	var layers: Array = [
		{"__identifier": "Gameplay", "__type": "IntGrid", "__cWid": 7,
			"__gridSize": 16, "intGridCsv": [1, 2, 3, 4, 5, 6, 7]},
		{"__identifier": "GameplayAreas", "__type": "Entities", "__pxTotalOffsetX": 8,
			"__pxTotalOffsetY": 16, "entityInstances": [
				{"__identifier": "DashGapArea", "px": [16, 32], "width": 16, "height": 16, "__pivot": [0, 0]}]},
	]
	gameplay.call(&"configure", layers)
	await physics_frame
	await physics_frame
	_expect(gameplay.get_node("MapLimits").get_child_count() == 3, "MapLimit/Solid/Hazard must create solid cells")
	_expect((gameplay.get("start_position") as Vector2) == Vector2(56, 8), "Start center changed")
	_expect(bool(gameplay.call(&"is_gap_point", Vector2(24, 8))), "DashGap no longer recognized")
	_expect(bool(gameplay.call(&"is_gap_point", Vector2(30, 54))), "DashGapArea offset was lost")
	var blocker: CollisionShape2D = gameplay.get_node("DoorBlocks").get_child(0) as CollisionShape2D
	_expect(not blocker.disabled, "DoorBlock should start closed")
	gameplay.call(&"set_doors_locked", false)
	await physics_frame
	await physics_frame
	_expect(blocker.disabled, "DoorBlock cannot unlock")
	gameplay.call(&"set_doors_locked", true)
	await physics_frame
	await physics_frame
	_expect(not blocker.disabled, "DoorBlock cannot lock")
	var map_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var definitions: Dictionary = map_data.defs as Dictionary
	for entity: Dictionary in definitions.entities:
		_expect(str(entity.identifier) in ["DashGapArea", "GameplayTrigger", "WaterArea", "AmbientArea", "WaterShoreOverride", "Warp", "DoorControl"], "Unexpected character/decorative-door entity remains")
	for definition: Dictionary in definitions.layers:
		var identifier: String = str(definition.identifier)
		_expect(identifier not in ["Entities", "Collisions"] and not identifier.begins_with("Doors") and not identifier.begins_with("Throne"), "Obsolete layer remains")
		_expect(not str(definition.doc).is_empty(), "Layer description missing")
	gameplay.free()
	if _failures == 0:
		print("LDTK CLEANUP PASS: utility palette, collision categories, Start, DashGap/area offsets, DoorBlock lock, descriptions, no character/decorative-door/throne layers")
	quit(0 if _failures == 0 else 1)
