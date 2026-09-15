extends Control
## A compact screen-edge arrow that points from Nox toward the returned stair.

const FILL_COLOR := Color(0.96, 0.85, 0.46, 1.0)
const OUTLINE_COLOR := Color(0.10, 0.04, 0.07, 1.0)
const BOTTOM_MARGIN := 18.0

var target: Node2D
var source: Node2D


func point_to(target_node: Node2D, source_node: Node2D) -> void:
	target = target_node
	source = source_node
	show()
	queue_redraw()


func clear() -> void:
	target = null
	source = null
	hide()


func _process(_delta: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(source):
		clear()
		return
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(target) or not is_instance_valid(source):
		return
	var canvas_transform := get_viewport().get_canvas_transform()
	var target_screen: Vector2 = canvas_transform * target.global_position
	var source_screen: Vector2 = canvas_transform * source.global_position
	var direction := source_screen.direction_to(target_screen)
	if direction.is_zero_approx():
		return

	var viewport_size := get_viewport_rect().size
	var anchor := Vector2(viewport_size.x * 0.5, viewport_size.y - BOTTOM_MARGIN)
	# The unrotated arrow faces down; rotating preserves that language for the stair.
	var rotation_offset := direction.angle() - PI * 0.5
	var local_points := PackedVector2Array([
		Vector2(-3.0, -10.0), Vector2(3.0, -10.0), Vector2(3.0, -1.0),
		Vector2(8.0, -1.0), Vector2(0.0, 9.0), Vector2(-8.0, -1.0),
		Vector2(-3.0, -1.0),
	])
	var points := PackedVector2Array()
	for point: Vector2 in local_points:
		points.append(anchor + point.rotated(rotation_offset))
	draw_colored_polygon(points, FILL_COLOR)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE_COLOR, 2.0, false)
