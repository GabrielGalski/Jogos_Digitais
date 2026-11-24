class_name CardTableCard
extends Node2D
## Damped reveal/drag and projected corners adapted from the archived opening.

const FOIL: Shader = preload("res://shaders/card_table_foil.gdshader")
const PATTERN: Texture2D = preload("res://assets/visual/cards/foil_pattern.png")
const BORDER_MASK: Texture2D = preload("res://assets/visual/cards/border_mask.png")

var card_id: String = ""
var aspect: int = 0
var order: int = 0
var on_table: bool = false
var table_position: Vector2 = Vector2.ZERO
var table_angle: float = 0.0
var target_position: Vector2 = Vector2.ZERO
var target_angle: float = 0.0
var normal_size: Vector2 = Vector2.ZERO
var focus_size: Vector2 = Vector2.ZERO
var target_size: Vector2 = Vector2.ZERO
var foil_tint: Color = Color.TRANSPARENT
var target_tilt: Vector2 = Vector2.ZERO
var inspected: bool = false
var current_tilt: Vector2 = Vector2.ZERO
var _display_size: Vector2 = Vector2.ZERO
var _angle: float = 0.0
var _foil_amount: float = 0.0
var _reveal_elapsed: float = 0.0
var _face: Polygon2D
var _shadow: Polygon2D
var _foil: ShaderMaterial
var _live_face: Sprite2D
var _live_source_size: Vector2


func configure(texture: Texture2D, id: String, group: int, index: int, visible_rect: Rect2, finish: Color = Color.TRANSPARENT) -> void:
	card_id = id
	aspect = group
	order = index
	foil_tint = finish
	var aspect_ratio: float = visible_rect.size.y / visible_rect.size.x
	normal_size = Vector2(88.0, 88.0 * aspect_ratio)
	focus_size = Vector2(228.0, 228.0 * aspect_ratio)
	target_size = normal_size
	_display_size = normal_size * 0.82
	# The Pillow generator publishes this crop from the actual source alpha bounds.
	var uv: PackedVector2Array = PackedVector2Array([
		visible_rect.position, Vector2(visible_rect.end.x, visible_rect.position.y),
		visible_rect.end, Vector2(visible_rect.position.x, visible_rect.end.y)])
	_shadow = Polygon2D.new()
	_shadow.texture = texture
	_shadow.uv = uv
	_shadow.color = Color(0.0, 0.0, 0.0, 0.38)
	add_child(_shadow)
	_face = Polygon2D.new()
	_face.texture = texture
	_face.uv = uv
	add_child(_face)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if foil_tint.a > 0.0:
		_foil = ShaderMaterial.new()
		_foil.shader = FOIL
		_foil.set_shader_parameter("foil_pattern", PATTERN)
		_foil.set_shader_parameter("border_mask", BORDER_MASK)
		_foil.set_shader_parameter("border_tint", foil_tint)
		_face.material = _foil
	_reveal_elapsed = -float(index) * 0.025
	modulate.a = 0.0


func set_inspected(value: bool) -> void:
	inspected = value
	if not value:
		target_tilt = Vector2.ZERO


func use_live_face(face: Sprite2D, source_size: Vector2) -> void:
	_live_face = face
	_live_source_size = source_size
	_face.hide()
	_shadow.hide()
	add_child(face)


func contains_point(pointer: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(pointer - position, _face.polygon)


func _process(delta: float) -> void:
	_reveal_elapsed += delta
	if _reveal_elapsed < 0.0:
		return
	modulate.a = minf(1.0, _reveal_elapsed / 0.24)
	var blend: float = 1.0 - exp(-15.0 * delta)
	position = position.lerp(target_position, blend)
	_display_size = _display_size.lerp(target_size, blend)
	_angle = lerp_angle(_angle, target_angle, blend)
	current_tilt = current_tilt.lerp(target_tilt, blend)
	if _foil != null:
		_foil_amount = lerpf(_foil_amount, 1.0 if inspected else 0.88, blend)
		_foil.set_shader_parameter("view_tilt", current_tilt)
		_foil.set_shader_parameter("strength", _foil_amount)
	var half: Vector2 = _display_size * 0.5
	var corners: PackedVector2Array = PackedVector2Array([
		_project(Vector2(-half.x, -half.y)), _project(Vector2(half.x, -half.y)),
		_project(half), _project(Vector2(-half.x, half.y))])
	_face.polygon = corners
	_shadow.polygon = corners
	_shadow.position = Vector2(10.0, 15.0) if inspected else Vector2(2.0, 4.0)
	if _live_face != null:
		_live_face.scale = _display_size / _live_source_size * Vector2(cos(current_tilt.y), cos(current_tilt.x))
		_live_face.rotation = _angle


func _project(point: Vector2) -> Vector2:
	var rotated_y: float = point.y * cos(current_tilt.x)
	var depth_y: float = point.y * sin(current_tilt.x)
	var rotated_x: float = point.x * cos(current_tilt.y) + depth_y * sin(current_tilt.y)
	var depth: float = -point.x * sin(current_tilt.y) + depth_y * cos(current_tilt.y)
	var perspective: float = 650.0 / (650.0 + depth)
	return Vector2(rotated_x, rotated_y).rotated(_angle) * perspective
