extends RefCounted

const SCREEN_SIZE: Vector2i = Vector2i(480, 270)
const ROOM_SIZE: Vector2i = Vector2i(960, 270)
const CAMERA_MARGIN: int = 32
const RENDER_SIZE: Vector2i = Vector2i(1024, 334)
const PLATFORM_TOP: float = 116.0
const PLATFORM_BOTTOM: float = 172.0
const CORRIDOR_TOP: float = 152.0
const CORRIDOR_BOTTOM: float = 208.0
const LOWER_WALL_BOTTOM: float = 232.0
const FLOOR_DEPTH: float = 56.0
const DEPTH_SKEW: float = 24.0 / FLOOR_DEPTH
const STEP_HEIGHT: float = 12.0
const STEP_WIDTH: float = 24.0
const FIRST_STEP_U: float = 96.0


static func level_at(ground_u: float) -> int:
	return clampi(3 - int(floor((ground_u - FIRST_STEP_U) / STEP_WIDTH)) - 1, 0, 3)


static func height_at(ground_u: float) -> float:
	return float(level_at(ground_u)) * STEP_HEIGHT


static func project_floor(ground: Vector2, elevation: float) -> Vector2:
	return Vector2(ground.x - ground.y * DEPTH_SKEW, CORRIDOR_TOP + ground.y - elevation)


static func walkable_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, PLATFORM_TOP),
		Vector2(96.0, PLATFORM_TOP),
		Vector2(96.0, 128.0),
		Vector2(120.0, 128.0),
		Vector2(120.0, 140.0),
		Vector2(144.0, 140.0),
		Vector2(144.0, CORRIDOR_TOP),
		Vector2(168.0, CORRIDOR_TOP),
		Vector2(float(ROOM_SIZE.x), CORRIDOR_TOP),
		Vector2(float(ROOM_SIZE.x), CORRIDOR_BOTTOM),
		Vector2(120.0, CORRIDOR_BOTTOM),
		Vector2(120.0, 196.0),
		Vector2(96.0, 196.0),
		Vector2(96.0, 184.0),
		Vector2(72.0, 184.0),
		Vector2(72.0, PLATFORM_BOTTOM),
		Vector2(0.0, PLATFORM_BOTTOM),
	])


static func stair_lines() -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	for step: int in range(3):
		var ground_u: float = FIRST_STEP_U + float(step) * STEP_WIDTH
		var high: float = float(3 - step) * STEP_HEIGHT
		# Both edges of the riser: each drop has a visible vertical face.
		lines.append(PackedVector2Array([
			project_floor(Vector2(ground_u, 0.0), high),
			project_floor(Vector2(ground_u, FLOOR_DEPTH), high),
		]))
		lines.append(PackedVector2Array([
			project_floor(Vector2(ground_u, 0.0), high - STEP_HEIGHT),
			project_floor(Vector2(ground_u, FLOOR_DEPTH), high - STEP_HEIGHT),
		]))
	return lines


static func lower_wall_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, PLATFORM_BOTTOM),
		Vector2(72.0, PLATFORM_BOTTOM),
		Vector2(72.0, 184.0),
		Vector2(96.0, 184.0),
		Vector2(96.0, 196.0),
		Vector2(120.0, 196.0),
		Vector2(120.0, CORRIDOR_BOTTOM),
		Vector2(float(ROOM_SIZE.x), CORRIDOR_BOTTOM),
		Vector2(float(ROOM_SIZE.x), LOWER_WALL_BOTTOM),
		Vector2(0.0, LOWER_WALL_BOTTOM),
	])
