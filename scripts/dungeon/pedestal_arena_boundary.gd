extends StaticBody2D
## Player-only containment clipped to connected, permitted terrain.

const PLAYER_BARRIER_LAYER: int = 16
const REGION: Script = preload("res://scripts/dungeon/pedestal_arena_region.gd")
var active: bool = false
var radius: float = 256.0
var region: Dictionary = {}
var _player: Player = null
var _polygon: CollisionPolygon2D = null
var _polygons: Array[CollisionPolygon2D] = []
var _height_query: Callable = Callable()
var _outlines: Array[PackedVector2Array] = []
var _last_valid: Vector2 = Vector2.ZERO


func configure(center: Vector2, arena_radius: float, player: Player, height_query: Callable, allowed_cells: Dictionary = {}) -> void:
	position = center
	radius = maxf(arena_radius, 64.0)
	_player = player
	_height_query = height_query
	_player.collision_mask |= PLAYER_BARRIER_LAYER
	collision_layer = PLAYER_BARRIER_LAYER
	collision_mask = 0
	z_index = -13
	process_physics_priority = 50
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var terrain: Dictionary = allowed_cells
	if terrain.is_empty():
		# Preserve standalone callers that intentionally have no LDtk terrain.
		terrain = {}
		var first: Vector2i = Vector2i(((center - Vector2.ONE * radius) / 16.0).floor())
		var ending: Vector2i = Vector2i(((center + Vector2.ONE * radius) / 16.0).ceil())
		for y: int in range(first.y, ending.y + 1):
			for x: int in range(first.x, ending.x + 1): terrain[Vector2i(x, y)] = true
	region = REGION.build(center, radius, terrain)
	for contour: PackedVector2Array in region.contours:
		var points: PackedVector2Array = PackedVector2Array()
		var outline: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in contour:
			points.append(point - center)
			var projected: Vector2 = point - center
			if _height_query.is_valid():
				projected.y -= roundf(float(_height_query.call(get_parent().to_global(point))))
			outline.append(projected)
		var perimeter: CollisionPolygon2D = CollisionPolygon2D.new()
		perimeter.name = "PerimeterCollision" if _polygons.is_empty() else "PerimeterCollision_%d" % _polygons.size()
		perimeter.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
		perimeter.polygon = points
		perimeter.disabled = true
		add_child(perimeter)
		_polygons.append(perimeter)
		_outlines.append(outline)
	if not _polygons.is_empty(): _polygon = _polygons[0]
	set_active(false)


func set_active(value: bool) -> void:
	active = value
	visible = value
	set_physics_process(value)
	for perimeter: CollisionPolygon2D in _polygons:
		perimeter.set_deferred("disabled", not value)
	if value and is_instance_valid(_player):
		_last_valid = REGION.closest_allowed_point(region, get_parent().to_local(_player.global_position), 9.0)
	queue_redraw()


func has_point(point: Vector2, clearance: float = 0.0) -> bool:
	return REGION.point_is_inside(region, point, clearance)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player) or _player.dead:
		set_active(false)
		return
	# A swept recovery never teleports across water to another permitted shore.
	var point: Vector2 = get_parent().to_local(_player.global_position)
	var corrected: Vector2 = REGION.clamp_motion(region, _last_valid, point, 9.0)
	_last_valid = corrected
	if not corrected.is_equal_approx(point):
		var normal: Vector2 = (point - corrected).normalized()
		_player.global_position = get_parent().to_global(corrected)
		_player.velocity -= normal * maxf(_player.velocity.dot(normal), 0.0)
		_player.knockback_velocity -= normal * maxf(_player.knockback_velocity.dot(normal), 0.0)
		_player.reset_physics_interpolation()


func _draw() -> void:
	if not active:
		return
	for outline: PackedVector2Array in _outlines:
		if outline.is_empty(): continue
		var line: PackedVector2Array = outline.duplicate()
		line.append(line[0])
		draw_polyline(line, Color(0.73, 0.79, 0.80, 0.92), 1.0, false)
