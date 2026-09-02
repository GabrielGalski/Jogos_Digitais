extends SceneTree

const ARENA_SCENE := preload("res://scenes/arena.tscn")
const EXPECTED_COLUMNS := 43
const EXPECTED_ROWS := 24
const EXPECTED_CELL_COUNT := EXPECTED_COLUMNS * EXPECTED_ROWS
const EXPECTED_INTERIOR_COUNT := (EXPECTED_COLUMNS - 2) * (EXPECTED_ROWS - 2)


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var arena := ARENA_SCENE.instantiate() as Arena
	if arena == null:
		_fail("arena.tscn should instantiate an Arena node")
		return

	if arena.get_floor_bounds() != Rect2(-344.0, -192.0, 688.0, 384.0):
		_fail("the native platform should preserve the complete floor rectangle")
		return
	if arena.get_player_bounds() != Rect2(-336.0, -184.0, 672.0, 368.0):
		_fail("player bounds should remain inside the platform")
		return
	if arena.get_script().is_tool():
		_fail("arena.gd should not generate editor content")
		return

	var ground := arena.get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		_fail("arena.tscn should contain a native Ground TileMapLayer")
		return
	if arena.get_child_count() != 1:
		_fail("the arena visualization should contain only the ground platform")
		return
	if ground.position != Vector2(-344.0, -192.0):
		_fail("the TileMapLayer origin should align with the platform top-left corner")
		return
	if ground.tile_set == null or ground.tile_set.tile_size != Vector2i(16, 16):
		_fail("the native TileSet should use 16x16 cells")
		return
	if ground.get_used_rect() != Rect2i(0, 0, EXPECTED_COLUMNS, EXPECTED_ROWS):
		_fail("the serialized TileMapLayer should cover exactly 43x24 cells")
		return
	if ground.get_used_cells().size() != EXPECTED_CELL_COUNT:
		_fail("the platform should serialize all 1032 cells")
		return
	if ground.position + ground.map_to_local(Vector2i(0, 0)) != Vector2(-336.0, -184.0):
		_fail("the first tile center should align with the logical player boundary")
		return
	if ground.position + ground.map_to_local(Vector2i(42, 23)) != Vector2(336.0, 184.0):
		_fail("the last tile center should align with the logical player boundary")
		return

	var atlas := ground.tile_set.get_source(0) as TileSetAtlasSource
	if atlas == null:
		_fail("TileSet source 0 should be a native atlas source")
		return
	if atlas.texture == null or atlas.texture.resource_path != "res://assets/tiles/floor/floor_tileset.png":
		_fail("the native atlas should reference the floor tileset texture directly")
		return
	if atlas.texture.get_size() != Vector2(64.0, 48.0):
		_fail("the floor atlas should preserve its complete 64x48 texture")
		return
	if atlas.texture_region_size != Vector2i(16, 16):
		_fail("the native atlas regions should measure 16x16 pixels")
		return

	var expected_edges := {
		Vector2i(0, 0): Vector2i(0, 0),
		Vector2i(42, 0): Vector2i(3, 0),
		Vector2i(0, 23): Vector2i(0, 2),
		Vector2i(42, 23): Vector2i(3, 2),
		Vector2i(20, 0): Vector2i(1, 0),
		Vector2i(20, 23): Vector2i(1, 2),
		Vector2i(0, 12): Vector2i(0, 1),
		Vector2i(42, 12): Vector2i(3, 1),
	}
	for cell: Vector2i in expected_edges:
		if ground.get_cell_source_id(cell) != 0:
			_fail("border cell %s should use atlas source 0" % cell)
			return
		if ground.get_cell_atlas_coords(cell) != expected_edges[cell]:
			_fail("incorrect atlas region for border cell %s" % cell)
			return

	var variant_count := 0
	var rotation_usage := {
		0: 0,
		TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_H: 0,
		TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V: 0,
		TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_V: 0,
	}
	for row in range(1, EXPECTED_ROWS - 1):
		for column in range(1, EXPECTED_COLUMNS - 1):
			var cell := Vector2i(column, row)
			if ground.get_cell_source_id(cell) != 0:
				_fail("interior cell %s should use atlas source 0" % cell)
				return
			var atlas_coords := ground.get_cell_atlas_coords(cell)
			var alternative := ground.get_cell_alternative_tile(cell)
			if atlas_coords == Vector2i(2, 1):
				variant_count += 1
				if not rotation_usage.has(alternative):
					_fail("variant cell %s uses an unexpected transform" % cell)
					return
				rotation_usage[alternative] += 1
			elif atlas_coords != Vector2i(1, 1) or alternative != 0:
				_fail("interior cells should use only the two mapped center tiles")
				return

	if EXPECTED_INTERIOR_COUNT != 902 or variant_count != 318:
		_fail("the deterministic platform should preserve 318 variants among 902 interior cells")
		return
	for usage: int in rotation_usage.values():
		if usage == 0:
			_fail("center variants should use all four quarter-turn orientations")
			return

	print("ARENA_TILEMAP_SMOKE_OK %d/%d %.2f%%" % [
		variant_count,
		EXPECTED_INTERIOR_COUNT,
		float(variant_count) / float(EXPECTED_INTERIOR_COUNT) * 100.0,
	])
	arena.free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
