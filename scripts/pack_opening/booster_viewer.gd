class_name BoosterViewer
extends Control

signal booster_opened(cards: Array[CardDefinition])
signal viewer_closed()
signal audio_cue_requested(cue: StringName)

@export var opening_profile: PackOpeningProfile = preload("res://resources/visual/pack_opening.tres")

const HOVER_SCALE := 1.055
const FOCAL_LENGTH := 520.0
const REFERENCE_HEIGHT := 270.0
const BODY_GRAVITY := 960.0
const TEAR_GRAVITY := 1200.0
const SHADOW_OFFSET := Vector2(5.0, 8.0)

# The printed volume takes precedence over the names of the blue and green files.
const PACKS: Array[Texture2D] = [
	preload("res://assets/boosters/base/booster_base_vol1.png"),
	preload("res://assets/boosters/base/booster_base_vol3.png"),
	preload("res://assets/boosters/base/booster_base_vol2.png"),
]

enum BoosterState {
	IDLE,
	OPENING,
	CARDS,
	CUTTING
}

@onready var card_stack: BoosterCardStack = $CardsAnchor
@onready var booster_anchor: Node2D = $BoosterAnchor
@onready var booster: Polygon2D = $BoosterAnchor/Booster
@onready var shadow: Polygon2D = $BoosterAnchor/Shadow
@onready var tear: Polygon2D = $BoosterAnchor/Tear
@onready var tear_shadow: Polygon2D = $BoosterAnchor/TearShadow
@onready var back_fx: PackOpeningFX = $BurstBack
@onready var front_fx: PackOpeningFX = $BurstFront
@onready var opening_pointer: Node2D = $OpeningPointer
@onready var background: ColorRect = $Background

var _reward: Array[CardDefinition] = []
var _consumed: bool = false
var _owns_cursor: bool = false
var _previous_mouse_mode: Input.MouseMode
var _game_cursor: CanvasLayer
var _game_cursor_was_visible: bool = false
var _pack: Texture2D
var _body: Texture2D
var _seal: Texture2D
var _pack_size: Vector2
var _pack_bounds: Rect2
var _seal_row: float
var _tear_pivot: Vector2
var elapsed := 0.0
var current_scale: float = 0.85
var current_tilt_x := 0.0
var current_tilt_y := 0.0
var current_rotation := 0.0
var float_offset := 0.0
var hovered := false
var booster_state := BoosterState.IDLE
var opening_elapsed := 0.0
var slash: PackSlashController = PackSlashController.new()
var cut_direction: float = 1.0
var pieces_released: bool = false


func _ready() -> void:
	back_fx.profile = opening_profile
	front_fx.profile = opening_profile
	card_stack.card_presented.connect(_on_card_presented)
	card_stack.card_dropped.connect(_on_card_dropped)
	resized.connect(_center_booster)
	_center_booster()
	set_process(false)


func open_pack(volume: int, reward: Array[CardDefinition]) -> void:
	_reward = reward.duplicate()
	_consumed = false
	_pack = PACKS[volume - 1]
	_prepare_pack_art()
	card_stack.set_reward(_reward)
	_capture_cursor()
	show()
	set_process(true)
	elapsed = 0.0
	_restore_booster()


func close_viewer() -> void:
	if not visible:
		return
	hide()
	set_process(false)
	slash.reset()
	back_fx.reset_fx()
	front_fx.reset_fx()
	card_stack.reset_cards()
	_restore_cursor()
	viewer_closed.emit()


func _exit_tree() -> void:
	_restore_cursor()


func _capture_cursor() -> void:
	if _owns_cursor:
		return
	_owns_cursor = true
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_game_cursor = get_node_or_null("/root/GameCursor") as CanvasLayer
	if _game_cursor != null:
		_game_cursor_was_visible = _game_cursor.visible
		_game_cursor.hide()


func _restore_cursor() -> void:
	if not _owns_cursor:
		return
	_owns_cursor = false
	Input.mouse_mode = _previous_mouse_mode
	if is_instance_valid(_game_cursor):
		_game_cursor.visible = _game_cursor_was_visible
	_game_cursor = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready() and booster_state == BoosterState.CUTTING:
		_cancel_cut()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			close_viewer()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE:
			if booster_state == BoosterState.CARDS:
				close_viewer()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pointer_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			if booster_state == BoosterState.IDLE:
				var line: PackedVector2Array = _seal_points()
				var axis: Vector2 = (line[1] - line[0]).normalized()
				var seal_transform: Transform2D = Transform2D(axis, Vector2(-axis.y, axis.x), line[0])
				slash.begin(pointer_position, Rect2(0.0, -2.0, line[0].distance_to(line[1]), 4.0), opening_profile.cut_coverage, opening_profile.cut_tolerance, seal_transform)
				booster_state = BoosterState.CUTTING
				front_fx.begin_stroke(pointer_position)
				audio_cue_requested.emit(&"cut_started")
		elif booster_state == BoosterState.CUTTING:
			_cancel_cut()
		if booster_state != BoosterState.CARDS:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and booster_state == BoosterState.CUTTING:
		var pointer_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		front_fx.trace_to(pointer_position)
		var confirmed: bool = slash.advance(pointer_position)
		if confirmed:
			_start_opening()
		elif not slash.active:
			_cancel_cut()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	elapsed += delta
	if booster_state == BoosterState.CUTTING:
		return

	if booster_state == BoosterState.OPENING:
		_update_opening(delta)
		return

	if booster_state == BoosterState.CARDS:
		hovered = false
		return

	var mouse_position: Vector2 = opening_pointer.position
	var visual_center := size * 0.5 + Vector2(0.0, float_offset)
	var hover_half_size: Vector2 = _pack_bounds.size * current_scale * 0.56
	hovered = _is_mouse_over_booster(mouse_position)

	var desired_scale: float = _fitted_scale()
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
	var line: PackedVector2Array = _seal_points()
	front_fx.show_guide(line[0], line[1])


func _start_opening() -> void:
	if _consumed or booster_state != BoosterState.CUTTING or not slash.completed:
		return
	booster_state = BoosterState.OPENING
	_consumed = true
	cut_direction = slash.direction
	opening_elapsed = 0.0
	hovered = false
	front_fx.finish_cut()
	audio_cue_requested.emit(&"cut_confirmed")
	booster_opened.emit(_reward)


func _update_opening(delta: float) -> void:
	opening_elapsed += delta
	current_scale = _damp(current_scale, _fitted_scale(), 14.0, delta)
	current_tilt_x = _damp(current_tilt_x, 0.0, 13.0, delta)
	current_tilt_y = _damp(current_tilt_y, 0.0, 13.0, delta)
	current_rotation = _damp(current_rotation, 0.0, 10.0, delta)
	float_offset = _damp(float_offset, 0.0, 10.0, delta)
	_center_booster()
	_update_meshes()
	var windup: float = maxf(opening_profile.shake_duration, 0.01)
	if opening_elapsed < windup:
		var progress: float = opening_elapsed / windup
		var shake: float = smoothstep(0.0, 0.20, progress) * (1.0 - smoothstep(0.70, 1.0, progress))
		var offset: Vector2 = Vector2(sin(opening_elapsed * 76.0), sin(opening_elapsed * 97.0) * 0.48)
		var squash: float = sin(progress * PI) * 0.08
		_apply_body_pose(
			offset * opening_profile.shake_pixels * shake * _layout_fit(),
			sin(opening_elapsed * 81.0) * shake * 0.09,
			Vector2(1.0 + squash, 1.0 - squash)
		)
		return

	if not pieces_released:
		_release_pack()
	var fall_time: float = opening_elapsed - windup
	_apply_drop(fall_time)
	var background_material: ShaderMaterial = background.material as ShaderMaterial
	if background_material != null:
		background_material.set_shader_parameter("reveal_pulse", (1.0 - smoothstep(0.0, 0.35, fall_time)) * 0.85)
	if _below_view(booster) and _below_view(tear):
		booster_state = BoosterState.CARDS
		booster.hide()
		shadow.hide()
		tear.hide()
		tear_shadow.hide()
		card_stack.finish_reveal()
		audio_cue_requested.emit(&"cards_settled")


func _release_pack() -> void:
	pieces_released = true
	_set_booster_texture(_body)
	tear.show()
	tear_shadow.show()
	# The falling foil uncovers the stationary stack from its top edge.
	card_stack.begin_reveal()
	var seal_points: PackedVector2Array = _seal_points()
	var burst_center: Vector2 = seal_points[0].lerp(seal_points[1], 0.5)
	back_fx.burst(burst_center, cut_direction)
	front_fx.burst(burst_center, cut_direction)
	audio_cue_requested.emit(&"seal_ripped")
	audio_cue_requested.emit(&"tear_flick")
	audio_cue_requested.emit(&"reveal_burst")


func _apply_drop(time: float) -> void:
	var motion_scale: float = size.y / REFERENCE_HEIGHT
	var body: Vector2 = Vector2(-cut_direction * 22.0 * time, 34.0 * time + 0.5 * BODY_GRAVITY * time * time)
	_apply_body_pose(body * motion_scale, -cut_direction * 0.72 * time)
	var seal: Vector2 = Vector2(cut_direction * 118.0 * time, -86.0 * time + 0.5 * TEAR_GRAVITY * time * time)
	var seal_angle: float = cut_direction * 5.2 * time
	var pivot: Vector2 = _tear_pivot * current_scale
	tear.rotation = seal_angle
	tear.position = seal * motion_scale + pivot - pivot.rotated(seal_angle)
	tear_shadow.rotation = seal_angle
	tear_shadow.position = tear.position + SHADOW_OFFSET * _layout_fit()


func _apply_body_pose(offset: Vector2, angle: float = 0.0, squash: Vector2 = Vector2.ONE) -> void:
	booster.position = offset
	booster.rotation = angle
	booster.scale = squash
	shadow.position = offset + SHADOW_OFFSET * _layout_fit()
	shadow.rotation = angle
	shadow.scale = squash


func _below_view(piece: Polygon2D) -> bool:
	var pose: Transform2D = booster_anchor.transform * piece.transform
	for corner: Vector2 in piece.polygon:
		if (pose * corner).y < size.y:
			return false
	return true


func _restore_booster() -> void:
	booster_state = BoosterState.IDLE
	slash.reset()
	back_fx.reset_fx()
	front_fx.reset_fx()
	var background_material: ShaderMaterial = background.material as ShaderMaterial
	if background_material != null:
		background_material.set_shader_parameter("reveal_pulse", 0.0)
	opening_elapsed = 0.0
	pieces_released = false
	hovered = false
	booster.visible = true
	shadow.visible = true
	tear.visible = false
	tear_shadow.visible = false
	card_stack.reset_cards()
	_set_booster_texture(_pack)
	_set_tear_texture(_seal)

	current_scale = _fitted_scale()
	current_tilt_x = 0.0
	current_tilt_y = 0.0
	current_rotation = 0.0
	float_offset = 0.0

	_center_booster()
	_update_meshes()
	_apply_body_pose(Vector2.ZERO)
	opening_pointer.position = get_local_mouse_position().round()
	audio_cue_requested.emit(&"pack_presented")


func _set_booster_texture(texture: Texture2D) -> void:
	booster.texture = texture
	shadow.texture = texture


func _set_tear_texture(texture: Texture2D) -> void:
	tear.texture = texture
	tear_shadow.texture = texture


func _is_mouse_over_booster(mouse_position: Vector2) -> bool:
	var visual_center := size * 0.5 + Vector2(0.0, float_offset)
	var hover_half_size: Vector2 = _pack_bounds.size * current_scale * 0.56
	return Rect2(visual_center - hover_half_size, hover_half_size * 2.0).has_point(mouse_position)


func _center_booster() -> void:
	booster_anchor.position = size * 0.5 + Vector2(0.0, float_offset)
	card_stack.position = size * 0.5
	card_stack.scale = Vector2.ONE * _layout_fit()
	if background.material is ShaderMaterial:
		(background.material as ShaderMaterial).set_shader_parameter("logical_size", size)
	if booster_state == BoosterState.CUTTING:
		_cancel_cut()


func _seal_points() -> PackedVector2Array:
	# Project the same source coordinates as the pack mesh, including its tilt.
	var half_width: float = (_pack_bounds.size.x * 0.5 - 5.0) * current_scale
	var row: float = (_seal_row - _pack_size.y * 0.5) * current_scale
	return PackedVector2Array([
		booster_anchor.position + _project_corner(-half_width, row),
		booster_anchor.position + _project_corner(half_width, row)
	])


func _cancel_cut() -> void:
	slash.reset()
	booster_state = BoosterState.IDLE
	front_fx.finish_cut()
	audio_cue_requested.emit(&"cut_cancelled")


func _on_card_presented(_index: int) -> void:
	audio_cue_requested.emit(&"card_reveal")


func _on_card_dropped() -> void:
	audio_cue_requested.emit(&"card_drop")


func _prepare_pack_art() -> void:
	var image: Image = _pack.get_image()
	if image.is_compressed():
		image.decompress()
	_pack_size = Vector2(image.get_size())
	_pack_bounds = Rect2(image.get_used_rect())
	# The tear line of the original foil is immediately below the top crimp.
	_seal_row = roundf(_pack_bounds.position.y + _pack_bounds.size.y * 0.11)
	var strip: Rect2i = Rect2i(0, 0, image.get_width(), int(_seal_row))
	var body: Rect2i = Rect2i(0, strip.end.y, image.get_width(), image.get_height() - strip.end.y)
	_body = _pack_piece(image, body)
	_seal = _pack_piece(image, strip)
	_tear_pivot = Vector2(_pack_bounds.get_center().x, (_pack_bounds.position.y + _seal_row) * 0.5) - _pack_size * 0.5
	var texture_uv := PackedVector2Array([
		Vector2.ZERO,
		Vector2(_pack_size.x, 0.0),
		_pack_size,
		Vector2(0.0, _pack_size.y)
	])
	booster.uv = texture_uv
	shadow.uv = texture_uv
	tear.uv = texture_uv
	tear_shadow.uv = texture_uv


func _pack_piece(source: Image, region: Rect2i) -> Texture2D:
	var piece: Image = Image.create_empty(source.get_width(), source.get_height(), false, source.get_format())
	piece.fill(Color.TRANSPARENT)
	piece.blit_rect(source, region, region.position)
	return ImageTexture.create_from_image(piece)


func _fitted_scale() -> float:
	return opening_profile.pack_scale * _layout_fit()


func _layout_fit() -> float:
	return clampf(size.y / REFERENCE_HEIGHT, 0.01, 1.0)


func _update_meshes() -> void:
	var corners := _get_projected_corners()
	booster.polygon = corners
	shadow.polygon = corners
	tear.polygon = corners
	tear_shadow.polygon = corners


func _get_projected_corners() -> PackedVector2Array:
	var half_width: float = _pack_size.x * current_scale * 0.5
	var half_height: float = _pack_size.y * current_scale * 0.5
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
