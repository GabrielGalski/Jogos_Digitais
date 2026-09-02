extends Node2D
class_name Arena

const TILE_SIZE := 16
const ARENA_COLUMNS := 43
const ARENA_ROWS := 24
const ARENA_SIZE := Vector2(ARENA_COLUMNS * TILE_SIZE, ARENA_ROWS * TILE_SIZE)
const ARENA_CENTER := Vector2.ZERO
const PLAYER_MARGIN := Vector2(8.0, 8.0)


func get_player_bounds() -> Rect2:
	return get_floor_bounds().grow(-PLAYER_MARGIN.x)


func get_floor_bounds() -> Rect2:
	return Rect2(ARENA_CENTER - ARENA_SIZE * 0.5, ARENA_SIZE)
