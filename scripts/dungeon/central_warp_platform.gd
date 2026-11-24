extends Node2D
## Source-space mapping scaled to the LDtk entity, with relief and Y-sorted solid pillars.

const VISUAL: Script = preload("res://scripts/visual/warp_visual.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const PROP_COVER: Script = preload("res://scripts/combat/projectile_prop_cover.gd")
const SOURCE_CENTER: Vector2 = VISUAL.CENTRAL_SOURCE_CENTER
const ACTOR_BASELINE_OFFSET: float = 8.0
var _top: PackedVector2Array = PackedVector2Array([
	Vector2(48, 31), Vector2(144, 31), Vector2(190, 76), Vector2(190, 140),
	Vector2(144, 184), Vector2(48, 184), Vector2(2, 140), Vector2(2, 76)])
const PILLAR_NAMES: Array[String] = ["NorthWest", "NorthEast", "SouthWest", "SouthEast"]
const PILLAR_FEET: Array[Vector2] = [Vector2(37, 63), Vector2(155, 63), Vector2(37, 162), Vector2(155, 162)]
var elevation: float = 8.0
var ramp_width: float = 8.0
var display_scale: float = 1.0
var pillars: Array[Node2D] = []


func configure(presentation: Node2D, description: Dictionary) -> void:
	elevation = clampf(float(description.get("HeightPx", 8)), 0.0, 32.0)
	ramp_width = clampf(float(description.get("RampWidth", 8)), 1.0, 24.0)
	display_scale = presentation.scale.x
	y_sort_enabled = true
	for index: int in range(PILLAR_FEET.size()):
		var foot: Vector2 = (PILLAR_FEET[index] - SOURCE_CENTER) * display_scale
		var column: Node2D = Node2D.new()
		column.name = PILLAR_NAMES[index]
		column.z_index = 2
		column.z_as_relative = false
		column.position = foot + Vector2(0.0, elevation + (7.0 * display_scale) - ACTOR_BASELINE_OFFSET)
		var footprint_center: Vector2 = foot + Vector2(0.0, elevation)
		column.set_meta(&"footprint", Rect2(footprint_center - Vector2(10, 5) * display_scale, Vector2(20, 10) * display_scale))
		add_child(column)
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = "PillarSprite"
		sprite.texture = VISUAL.CENTRAL_PILLARS[index]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = false
		# All four files are aligned to the same full-size canvas as the base.
		sprite.scale = Vector2.ONE * display_scale
		sprite.position = presentation.position - SOURCE_CENTER * display_scale - column.position
		column.add_child(sprite)
		PROP_COVER.attach(sprite)
		var solid: StaticBody2D = StaticBody2D.new()
		solid.name = "SolidBase"
		solid.collision_layer = 1
		solid.collision_mask = 0
		solid.position = footprint_center - column.position
		solid.add_to_group(&"central_warp_pillars")
		solid.add_to_group(CONTACTS.MOVEMENT_ONLY)
		var shape: CapsuleShape2D = CapsuleShape2D.new()
		shape.radius = 5.0 * display_scale
		shape.height = 20.0 * display_scale
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.name = "Footprint"
		collider.shape = shape
		collider.rotation = PI * 0.5
		solid.add_child(collider)
		column.add_child(solid)
		pillars.append(column)


func _stairs() -> Rect2:
	# Feet are on the map plane; the top is projected up by elevation.
	return Rect2(-41 * display_scale, 78 * display_scale + elevation, 82 * display_scale, 68 * display_scale - elevation)


func supports_feet(world_feet: Vector2) -> bool:
	var point: Vector2 = to_local(world_feet)
	return _stairs().has_point(point) or Geometry2D.is_point_in_polygon((point - Vector2(0, elevation)) / display_scale + SOURCE_CENTER, _top)


func height_at(world_feet: Vector2) -> float:
	var point: Vector2 = to_local(world_feet)
	var stairs: Rect2 = _stairs()
	if stairs.has_point(point):
		return elevation * clampf((stairs.end.y - point.y) / stairs.size.y, 0.0, 1.0)
	var source_point: Vector2 = (point - Vector2(0, elevation)) / display_scale + SOURCE_CENTER
	if not Geometry2D.is_point_in_polygon(source_point, _top):
		return 0.0
	var edge_distance: float = INF
	for index: int in range(_top.size()):
		# The southern stair joins the raised surface continuously, without a low seam.
		if index == 4 and absf(point.x) <= 41.0 * display_scale:
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(source_point, _top[index], _top[(index + 1) % _top.size()])
		edge_distance = minf(edge_distance, source_point.distance_to(closest) * display_scale)
	return elevation * clampf(edge_distance / ramp_width, 0.0, 1.0)
