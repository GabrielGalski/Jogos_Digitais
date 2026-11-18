extends SceneTree
## A private LDtk edit must change the real arena's art, support, walls and spawns.
const SCENE: PackedScene = preload("res://scenes/bosses/elemental_golem_arena.tscn")
const MAP: String = "res://monster_booster.ldtk"
const COPY: String = "res://tmp/elemental_ldtk_edit_test.ldtk"
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var original_hash: String = FileAccess.get_sha256(MAP)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP)) as Dictionary
	var level: Dictionary = {}
	for candidate: Dictionary in data.levels:
		if str(candidate.identifier) == "Room_4_Elemental": level = candidate
	check(Vector2(int(level.pxWid),int(level.pxHei))==Vector2(672,864),"LDtk room preserves current arena dimensions")
	var layers: Dictionary = {}
	for layer: Dictionary in level.layerInstances: layers[str(layer.__identifier)] = layer
	var floor_layer: Dictionary = layers.Floor_Elemental as Dictionary
	var floor_tiles: Array = floor_layer.gridTiles as Array
	check(floor_tiles.size()==4800,"LDtk contains all nine platforms and the enlarged corridor")
	var geometry: Dictionary = layers.ElementalLayout as Dictionary
	var columns: int = int(geometry.__cWid)
	# Cut an 8px hole in the central platform, and make one old void cell a wall.
	(geometry.intGridCsv as Array)[42+31*columns] = 1
	(geometry.intGridCsv as Array)[28+49*columns] = 2
	for index: int in range(floor_tiles.size()-1,-1,-1):
		var tile: Dictionary = floor_tiles[index] as Dictionary
		if int(tile.px[0]) == 336 and int(tile.px[1]) == 248: floor_tiles.remove_at(index)
	var edited: Dictionary = floor_tiles[0] as Dictionary
	edited["src"] = [24,24]
	edited["t"] = 51
	edited["f"] = 1
	for entity: Dictionary in (layers.GameplayAreas as Dictionary).entityInstances:
		if str(entity.__identifier) == "Warp": entity.px[0] = int(entity.px[0])+8
		elif str(entity.__identifier) == "ElementalGolemSpawn": entity.px[0] = int(entity.px[0])+16
	var file: FileAccess = FileAccess.open(COPY,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var arena: Node2D = SCENE.instantiate() as Node2D
	arena.set("map_path",COPY)
	root.add_child(arena)
	current_scene = arena
	var layout: Node2D = arena.get_node("CastleLayout") as Node2D
	var boss: CharacterBody2D = arena.get_node("ElementalGolem") as CharacterBody2D
	var player: Player = arena.get_node("Nox") as Player
	check((layout.get("bounds") as Rect2)==Rect2(-336,-336,672,864),"LDtk local coordinates retain the production combat origin")
	check(not bool(layout.call("supports_feet",Vector2(4,-84))),"A void painted in LDtk removes real floor support")
	check(boss.position==Vector2(16,-240),"Boss starts at its edited LDtk marker")
	check(player.position==Vector2(8,461),"Warp edit changes the real player arrival")
	var floor_map: TileMapLayer = layout.get_node("Floor_Elemental_0") as TileMapLayer
	check(floor_map.get_cell_source_id(Vector2i(42,31))==-1,"Removed LDtk floor artwork is absent in game")
	check(floor_map.get_cell_atlas_coords(Vector2i(3,4))==Vector2i(3,3),"Painted source tile is used directly by the runtime")
	check(floor_map.get_cell_alternative_tile(Vector2i(3,4))==TileSetAtlasSource.TRANSFORM_FLIP_H,"LDtk flip flags are preserved")
	check(str(floor_map.get_meta(&"ldtk_tileset"))=="assets/tiles/floor/dungeon/floor.png","Arena uses the original dungeon PNG")
	var constrained: Vector2 = layout.call("clamp_platform_point",Vector2(4,-84),4) as Vector2
	check(bool(layout.call("supports_feet",constrained)),"AI destinations avoid a newly painted hole")
	await physics_frame
	await physics_frame
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = Vector2(-108,60)
	query.collision_mask = 1
	check(not layout.get_world_2d().direct_space_state.intersect_point(query).is_empty(),"Painted wall creates real collision")
	check(FileAccess.get_sha256(MAP)==original_hash,"The live authored map remains unchanged by this test")
	arena.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY))
	print("ELEMENTAL_GOLEM_LDTK_REGRESSION "+("PASS" if failures.is_empty() else "FAIL "+str(failures.size())))
	quit(0 if failures.is_empty() else 1)
