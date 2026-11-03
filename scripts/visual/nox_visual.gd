class_name NoxVisual
extends AnimatedSprite2D
## Presentation shared by the gameplay character and the merchant's floor actor.

@export var contour_material: ShaderMaterial = preload("res://resources/visual/nox_contour.tres")

var facing: Vector2 = Vector2.DOWN
var walking: bool = false
var rolling: bool = false
var animation_locked: bool = false
var roll_direction: Vector2 = Vector2.RIGHT
var _horizontal_facing: float = 1.0
const SLIDE_SHADER: Shader = preload("res://shaders/player_dash_slide.gdshader")
var _slide_material: ShaderMaterial = null
var _roll_previous_material: Material = null
var _roll_previous_interpolation: Node.PhysicsInterpolationMode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT


func _ready() -> void:
	# Local silhouette treatment only; scenery, HUD and thrown sword stay nearest.
	material = null if _original_model() else contour_material
	_apply_pose()


func set_motion(direction: Vector2) -> void:
	if rolling or animation_locked:
		return
	walking = not direction.is_zero_approx()
	if walking:
		facing = direction.normalized()
	_apply_pose()


func face_direction(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		facing = direction.normalized()
	_apply_pose()


func reset_pose(direction: Vector2 = Vector2.DOWN) -> void:
	rolling = false
	rotation = 0.0
	walking = false
	facing = direction.normalized() if not direction.is_zero_approx() else Vector2.DOWN
	_apply_pose()


func _apply_pose() -> void:
	if rolling or animation_locked:
		return
	if _original_model():
		_apply_original_pose()
		return
	var lateral: bool = absf(facing.x) >= absf(facing.y)
	var next: StringName
	if lateral:
		flip_h = facing.x < 0.0
		next = (&"walk_left" if flip_h else &"walk_right") if walking else &"idle_side"
	else:
		flip_h = false
		var back: bool = facing.y < 0.0
		next = (&"walk_back" if back else &"walk_front") if walking else (&"idle_back" if back else &"idle_front")
	# Changing direction starts its authored sequence at frame zero.
	if animation != next or not is_playing():
		play(next)


func _original_model() -> bool:
	return sprite_frames != null and sprite_frames.has_animation(&"idle")


func _apply_original_pose() -> void:
	if absf(facing.x) > 0.15:
		_horizontal_facing = signf(facing.x)
	flip_h = _horizontal_facing < 0.0
	var next: StringName = &"run" if walking else &"idle"
	if animation != next or not is_playing():
		play(next)


func begin_roll(direction: Vector2) -> void:
	if not _original_model():
		return
	if rolling:
		end_roll()
	_roll_previous_material = material
	_roll_previous_interpolation = physics_interpolation_mode
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reset_physics_interpolation()
	if _slide_material == null:
		_slide_material = ShaderMaterial.new()
		_slide_material.shader = SLIDE_SHADER
	_slide_material.set_shader_parameter(&"slide_tint", Color.WHITE)
	material = _slide_material
	roll_direction = direction.normalized()
	facing = roll_direction
	walking = false
	rolling = true
	if animation != &"run" or not is_playing():
		play(&"run")
	set_roll_progress(0.0)


func set_roll_progress(progress: float) -> void:
	if not rolling:
		return
	var fraction: float = clampf(progress, 0.0, 1.0)
	# Keep Nox's actual run frame; the slide palette applies to every authored pose.
	if absf(roll_direction.x) > 0.15:
		_horizontal_facing = signf(roll_direction.x)
	flip_h = _horizontal_facing < 0.0
	rotation = 0.0
	var blend: float = smoothstep(0.0, 0.12, fraction) * (1.0 - smoothstep(0.72, 1.0, fraction))
	_slide_material.set_shader_parameter(&"slide_mix", blend)


func end_roll() -> void:
	if not rolling:
		return
	rolling = false
	material = _roll_previous_material
	_roll_previous_material = null
	physics_interpolation_mode = _roll_previous_interpolation
	reset_physics_interpolation()
	rotation = 0.0
	walking = false
	_apply_pose()
