extends Node2D
## Safe-room presentation only. The combat caster keeps its existing controller.
const CASTER: Script = preload("res://scripts/combat/deck_box_companion.gd")

@export var body_scale: float = 0.36
@export var side_distance: float = 26.0
@export var flight_height: float = 34.0
@export var follow_response: float = 7.0
@export var hover_amplitude: float = 2.0

var face: Sprite2D
var flight_position: Vector2 = Vector2.ZERO
var hover_time: float = 0.0
var shoulder: float = 1.0
var crossing_remaining: float = 0.0
var facing: Vector2 = Vector2.RIGHT
var mouse_look_enabled: bool = true


func _ready() -> void:
	face = Sprite2D.new()
	face.name = "Face"
	face.texture = CASTER.RIGHT
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	face.scale = Vector2.ONE * body_scale
	var edge_material: ShaderMaterial = ShaderMaterial.new()
	edge_material.shader = CASTER.EDGE_SHADER
	face.material = edge_material
	add_child(face)


func reset_follow(feet: Vector2) -> void:
	flight_position = feet + Vector2(shoulder * side_distance, -flight_height)
	global_position = flight_position
	reset_physics_interpolation()


func update_follow(feet: Vector2, movement: Vector2, delta: float) -> void:
	hover_time += delta
	if not movement.is_zero_approx():
		facing = movement.normalized()
	if absf(movement.x) > 0.1:
		var desired_side: float = -signf(movement.x)
		if desired_side != shoulder:
			shoulder = desired_side
			crossing_remaining = 0.3
	crossing_remaining = maxf(0.0, crossing_remaining - delta)
	var offset: Vector2 = Vector2(shoulder * side_distance, -flight_height)
	if crossing_remaining > 0.0:
		offset.y -= 6.0
	var desired: Vector2 = feet + offset
	if flight_position.distance_to(feet) > 180.0:
		reset_follow(feet)
	flight_position = flight_position.lerp(desired, 1.0 - exp(-follow_response * delta))
	global_position = flight_position + Vector2(0.0, sin(hover_time * 3.0) * hover_amplitude)
	_update_eyes()
	face.scale = Vector2.ONE * body_scale
	face.rotation = clampf((desired.x - flight_position.x) * 0.004, -0.08, 0.08)


func _update_eyes() -> void:
	# Movement owns the back-facing pose; the mouse must not paint eyes over it.
	if facing.y < -0.65:
		face.texture = CASTER.BACK
		return
	if not mouse_look_enabled:
		face.texture = CASTER.LEFT if facing.x < 0.0 else CASTER.RIGHT
		return
	var to_cursor: Vector2 = get_global_mouse_position() - global_position
	if absf(to_cursor.x) <= 8.0:
		face.texture = CASTER.FRONT
	else:
		face.texture = CASTER.LEFT if to_cursor.x < 0.0 else CASTER.RIGHT
