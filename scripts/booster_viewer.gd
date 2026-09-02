extends Control

const TEXTURE_SIZE := Vector2(128.0, 128.0)
const BASE_SCALE := 1.34
const HOVER_SCALE := 1.055
const FOCAL_LENGTH := 520.0
const VISUAL_HALF_SIZE := Vector2(33.0, 50.0)
const TEAR_PIVOT_FROM_CENTER := Vector2(0.0, -54.0)
const TEAR_FRAME_DURATION := 0.1
const TEAR_KICK_TIME := 0.38
const OPENING_DURATION := 1.45
const BODY_GRAVITY := 310.0
const TEAR_GRAVITY := 36.0
const TEAR_KICK_VELOCITY := Vector2(285.0, -205.0)

const CLOSED_TEXTURE := preload("res://assets/boosters/base/booster_base.png")
const FALLING_TEXTURE := preload("res://assets/boosters/opening/booster_open_body.png")
const TEAR_FRAMES := [
	preload("res://assets/boosters/opening/booster_tear_01.png"),
	preload("res://assets/boosters/opening/booster_tear_02.png"),
	preload("res://assets/boosters/opening/booster_tear_03.png")
]

enum BoosterState {
	IDLE,
	OPENING,
	CARDS
}

@onready var card_stack: BoosterCardStack = $CardsAnchor
@onready var booster_anchor: Node2D = $BoosterAnchor
@onready var booster: Polygon2D = $BoosterAnchor/Booster
@onready var shadow: Polygon2D = $BoosterAnchor/Shadow
@onready var tear: Polygon2D = $BoosterAnchor/Tear
@onready var tear_shadow: Polygon2D = $BoosterAnchor/TearShadow

var elapsed := 0.0
var current_scale := BASE_SCALE
var current_tilt_x := 0.0
var current_tilt_y := 0.0
var current_rotation := 0.0
var float_offset := 0.0
var hovered := false
var booster_state := BoosterState.IDLE
var opening_elapsed := 0.0
var tear_frame := 0
var tear_kicked := false
var body_position := Vector2.ZERO
var body_velocity := Vector2.ZERO
var body_rotation := 0.0
var tear_position := Vector2.ZERO
var tear_velocity := Vector2.ZERO
var tear_rotation := 0.0
var tear_angular_velocity := 0.0


func _ready() -> void:
	_set_texture_coordinates()
	resized.connect(_center_booster)
	_center_booster()
	set_process(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB:
			_toggle_viewer()
			get_viewport().set_input_as_handled()
			return
		if visible and (event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE):
			_restore_booster()
			get_viewport().set_input_as_handled()
			return

	if not visible:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if booster_state == BoosterState.IDLE and _is_mouse_over_booster(get_local_mouse_position()):
				_start_opening()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	elapsed += delta

	if booster_state == BoosterState.OPENING:
		_update_opening(delta)
		_update_opening_pose(delta)
		return

	if booster_state == BoosterState.CARDS:
		hovered = false
		return

	var mouse_position := get_local_mouse_position()
	var visual_center := size * 0.5 + Vector2(0.0, float_offset)
	var hover_half_size := VISUAL_HALF_SIZE * current_scale * 1.12
	hovered = _is_mouse_over_booster(mouse_position)

	var desired_scale := BASE_SCALE
	var desired_tilt_x := 0.0
	var desired_tilt_y := 0.0

	if hovered:
		var normalized_x := clampf(
			(mouse_position.x - visual_center.x) / maxf(hover_half_size.x, 1.0),
			-1.0,
			1.0
		)
		var normalized_y := clampf(
			(mouse_position.y - visual_center.y) / maxf(hover_half_size.y, 1.0),
			-1.0,
			1.0
		)
		desired_scale *= HOVER_SCALE
		desired_tilt_y = normalized_x * 0.16
		desired_tilt_x = -normalized_y * 0.11

	current_scale = _damp(current_scale, desired_scale, 14.0, delta)
	current_tilt_x = _damp(current_tilt_x, desired_tilt_x, 13.0, delta)
	current_tilt_y = _damp(current_tilt_y, desired_tilt_y, 13.0, delta)

	var idle_rotation := sin(elapsed * 0.72) * 0.012
	current_rotation = _damp(current_rotation, idle_rotation, 8.0, delta)
	var idle_float := sin(elapsed * 1.65) * 2.2
	var hover_lift := -10.0 if hovered else 0.0
	float_offset = _damp(float_offset, idle_float + hover_lift, 10.0, delta)

	_center_booster()
	_update_meshes()


func _toggle_viewer() -> void:
	visible = not visible
	set_process(visible)
	get_tree().paused = visible

	if visible:
		elapsed = 0.0
		_restore_booster(false)
	else:
		card_stack.reset_cards()


func _start_opening() -> void:
	booster_state = BoosterState.OPENING
	opening_elapsed = 0.0
	tear_frame = 0
	tear_kicked = false
	hovered = false
	_reset_piece_motion()
	_set_booster_texture(FALLING_TEXTURE)
	_set_tear_texture(TEAR_FRAMES[0])
	card_stack.begin_reveal()
	tear.visible = true
	tear_shadow.visible = true
	body_velocity = Vector2(-4.0, 8.0)
	body_rotation = 0.0
	_update_meshes()
	_apply_piece_transforms()


func _update_opening(delta: float) -> void:
	opening_elapsed += delta

	var next_tear_frame := mini(
		int(opening_elapsed / TEAR_FRAME_DURATION),
		TEAR_FRAMES.size() - 1
	)
	if next_tear_frame != tear_frame:
		tear_frame = next_tear_frame
		_set_tear_texture(TEAR_FRAMES[tear_frame])

	body_velocity.y += BODY_GRAVITY * delta
	body_position += body_velocity * delta
	body_rotation -= 0.24 * delta

	if opening_elapsed >= TEAR_KICK_TIME:
		if not tear_kicked:
			tear_kicked = true
			tear_velocity = TEAR_KICK_VELOCITY
			tear_angular_velocity = 4.8
		else:
			tear_velocity.y += TEAR_GRAVITY * delta
			tear_position += tear_velocity * delta
			tear_rotation += tear_angular_velocity * delta

	if opening_elapsed >= OPENING_DURATION:
		booster_state = BoosterState.CARDS
		booster.visible = false
		shadow.visible = false
		tear.visible = false
		tear_shadow.visible = false
		card_stack.finish_reveal()
		return


func _update_opening_pose(delta: float) -> void:
	if booster_state == BoosterState.CARDS:
		return

	current_scale = _damp(current_scale, BASE_SCALE, 14.0, delta)
	current_tilt_x = _damp(current_tilt_x, 0.0, 13.0, delta)
	current_tilt_y = _damp(current_tilt_y, 0.0, 13.0, delta)
	current_rotation = _damp(current_rotation, 0.0, 10.0, delta)
	float_offset = _damp(float_offset, 0.0, 10.0, delta)
	_center_booster()
	_update_meshes()
	_apply_piece_transforms()


func _restore_booster(with_entrance: bool = true) -> void:
	booster_state = BoosterState.IDLE
	opening_elapsed = 0.0
	tear_frame = 0
	tear_kicked = false
	hovered = false
	booster.visible = true
	shadow.visible = true
	tear.visible = false
	tear_shadow.visible = false
	card_stack.reset_cards()
	_set_booster_texture(CLOSED_TEXTURE)
	_set_tear_texture(TEAR_FRAMES[0])
	_reset_piece_motion()

	if with_entrance:
		current_scale = BASE_SCALE * 0.88
		float_offset = 3.0
	else:
		current_scale = BASE_SCALE
		current_tilt_x = 0.0
		current_tilt_y = 0.0
		current_rotation = 0.0
		float_offset = 0.0

	_center_booster()
	_update_meshes()
	_apply_piece_transforms()


func _set_booster_texture(texture: Texture2D) -> void:
	booster.texture = texture
	shadow.texture = texture


func _set_tear_texture(texture: Texture2D) -> void:
	tear.texture = texture
	tear_shadow.texture = texture


func _reset_piece_motion() -> void:
	body_position = Vector2.ZERO
	body_velocity = Vector2.ZERO
	body_rotation = 0.0
	tear_position = Vector2.ZERO
	tear_velocity = Vector2.ZERO
	tear_rotation = 0.0
	tear_angular_velocity = 0.0


func _apply_piece_transforms() -> void:
	var shadow_offset := Vector2(5.0, 8.0)
	booster.position = body_position
	booster.rotation = body_rotation
	booster.scale = Vector2.ONE
	shadow.position = body_position + shadow_offset
	shadow.rotation = body_rotation
	shadow.scale = Vector2.ONE

	var kick_scale := Vector2.ONE
	if tear_kicked:
		var kick_progress := clampf((opening_elapsed - TEAR_KICK_TIME) / 0.12, 0.0, 1.0)
		kick_scale = Vector2(
			lerpf(1.16, 1.0, kick_progress),
			lerpf(0.84, 1.0, kick_progress)
		)

	# Compensa o canvas transparente para girar em torno do centro visual do lacre.
	var tear_pivot := TEAR_PIVOT_FROM_CENTER * current_scale
	var transformed_pivot := Vector2(
		tear_pivot.x * kick_scale.x,
		tear_pivot.y * kick_scale.y
	).rotated(tear_rotation)
	var pivot_compensation := tear_pivot - transformed_pivot
	tear.position = tear_position + pivot_compensation
	tear.rotation = tear_rotation
	tear_shadow.position = tear_position + pivot_compensation + shadow_offset
	tear_shadow.rotation = tear_rotation
	tear.scale = kick_scale
	tear_shadow.scale = kick_scale


func _is_mouse_over_booster(mouse_position: Vector2) -> bool:
	var visual_center := size * 0.5 + Vector2(0.0, float_offset)
	var hover_half_size := VISUAL_HALF_SIZE * current_scale * 1.12
	return Rect2(visual_center - hover_half_size, hover_half_size * 2.0).has_point(mouse_position)


func _center_booster() -> void:
	booster_anchor.position = size * 0.5 + Vector2(0.0, float_offset)
	card_stack.position = size * 0.5


func _set_texture_coordinates() -> void:
	var texture_uv := PackedVector2Array([
		Vector2.ZERO,
		Vector2(TEXTURE_SIZE.x, 0.0),
		TEXTURE_SIZE,
		Vector2(0.0, TEXTURE_SIZE.y)
	])
	booster.uv = texture_uv
	shadow.uv = texture_uv
	tear.uv = texture_uv
	tear_shadow.uv = texture_uv


func _update_meshes() -> void:
	var corners := _get_projected_corners()
	booster.polygon = corners
	shadow.polygon = corners
	tear.polygon = corners
	tear_shadow.polygon = corners


func _get_projected_corners() -> PackedVector2Array:
	var half_width := TEXTURE_SIZE.x * current_scale * 0.5
	var half_height := TEXTURE_SIZE.y * current_scale * 0.5
	return PackedVector2Array([
		_project_corner(-half_width, -half_height),
		_project_corner(half_width, -half_height),
		_project_corner(half_width, half_height),
		_project_corner(-half_width, half_height)
	])


func _project_corner(local_x: float, local_y: float) -> Vector2:
	var cos_x := cos(current_tilt_x)
	var sin_x := sin(current_tilt_x)
	var cos_y := cos(current_tilt_y)
	var sin_y := sin(current_tilt_y)
	var cos_z := cos(current_rotation)
	var sin_z := sin(current_rotation)

	var projected_y_base := local_y * cos_x
	var depth_y := local_y * sin_x
	var projected_x_base := local_x * cos_y + depth_y * sin_y
	var depth := -local_x * sin_y + depth_y * cos_y
	var perspective := FOCAL_LENGTH / (FOCAL_LENGTH + depth)
	var projected_x := projected_x_base * perspective
	var projected_y := projected_y_base * perspective

	return Vector2(
		projected_x * cos_z - projected_y * sin_z,
		projected_x * sin_z + projected_y * cos_z
	)


func _damp(current: float, target: float, speed: float, delta: float) -> float:
	return target + (current - target) * exp(-speed * delta)
