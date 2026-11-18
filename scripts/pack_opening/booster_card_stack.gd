extends Node2D
class_name BoosterCardStack

signal card_presented(index: int)
signal card_dropped()

const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const CARD_WIDTH: float = 62.0
const FONT: Font = preload("res://assets/font/determination.ttf")
const STACK_POSITIONS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(-2.0, 2.0),
	Vector2(-4.0, 4.0)
]
const SPREAD_POSITIONS: Array[Vector2] = [
	Vector2(94.0, 8.0),
	Vector2(-94.0, 8.0),
	Vector2.ZERO
]
const SPREAD_ROTATIONS: Array[float] = [0.055, -0.055, 0.0]

enum CardMode {
	HIDDEN,
	REVEALING,
	STACKED,
	SPREAD
}

@onready var _slots: Array[Sprite2D] = [$Card1, $Card2, $Card3]

var cards: Array[Sprite2D] = []
var _card_scale: float = 1.0
var _half_size: Vector2
var mode := CardMode.HIDDEN
var reveal_step := 0
var stack_hover_amount := 0.0
var target_positions: Array[Vector2] = STACK_POSITIONS.duplicate()
var target_rotations: Array[float] = [0.0, 0.0, 0.0]
var dragged_card: Sprite2D
var drag_offset := Vector2.ZERO
var next_front_z := 10


func _ready() -> void:
	reset_cards()


func set_reward(reward: Array[CardDefinition]) -> void:
	var paths: Dictionary[StringName, String] = CATALOG.art_paths()
	var bounds: Rect2 = CATALOG.art_bounds()
	_card_scale = CARD_WIDTH / bounds.size.x
	_half_size = bounds.size * _card_scale * 0.5
	cards.clear()
	for index: int in range(_slots.size()):
		var slot: Sprite2D = _slots[index]
		slot.visible = index < reward.size()
		if not slot.visible:
			continue
		var definition: CardDefinition = reward[index]
		var code: StringName = CATALOG.alias(definition)
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = load(paths.get(code, "res://assets/cards/base/base_4x.png")) as Texture2D
		atlas.region = bounds
		slot.texture = atlas
		(slot.get_node("Shadow") as Sprite2D).texture = atlas
		(slot.get_node("Shadow") as Sprite2D).position = Vector2(3.0, 4.0) / _card_scale
		if code == &"M08" or not paths.has(code):
			var caption: Label = Label.new()
			caption.text = definition.display_name
			caption.position = Vector2(-bounds.size.x * 0.5, 26.0)
			caption.size.x = bounds.size.x
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.add_theme_font_override("font", FONT)
			caption.add_theme_font_size_override("font_size", 25)
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(caption)
		cards.append(slot)


func begin_reveal() -> void:
	mode = CardMode.REVEALING
	target_positions = STACK_POSITIONS.duplicate()
	target_rotations = [0.0, 0.0, 0.0]
	show()


func finish_reveal() -> void:
	mode = CardMode.STACKED
	set_process(true)


func reset_cards() -> void:
	mode = CardMode.HIDDEN
	visible = false
	dragged_card = null
	reveal_step = 0
	stack_hover_amount = 0.0
	next_front_z = 10
	set_process(false)

	for index in cards.size():
		var card := cards[index]
		card.position = STACK_POSITIONS[index]
		card.rotation = 0.0
		card.scale = Vector2.ONE * _card_scale
		card.modulate.a = 1.0
		card.z_index = 3 - index


func _process(delta: float) -> void:
	if mode == CardMode.STACKED:
		_update_stack(delta)
	elif mode == CardMode.SPREAD:
		_update_spread_cards(delta)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pointer: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			if mode == CardMode.STACKED and _contains_point(cards[reveal_step], pointer):
				_advance_stack()
				get_viewport().set_input_as_handled()
			elif mode == CardMode.SPREAD:
				var selected_card := _find_top_card(pointer)
				if selected_card:
					_begin_drag(selected_card, pointer)
					get_viewport().set_input_as_handled()
		elif dragged_card:
			_end_drag()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and dragged_card:
		var pointer: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var desired_position := pointer - drag_offset
		dragged_card.position = _clamp_card_position(desired_position)
		var index := cards.find(dragged_card)
		target_positions[index] = dragged_card.position
		dragged_card.rotation = clampf(event.relative.x * 0.012, -0.16, 0.16)
		get_viewport().set_input_as_handled()


func _update_stack(delta: float) -> void:
	var pointer := _pointer_position()
	var visible_card := cards[reveal_step]
	var pile_hovered := _contains_point(visible_card, pointer)
	stack_hover_amount = _damp(stack_hover_amount, 1.0 if pile_hovered else 0.0, 14.0, delta)

	var pointer_offset := clampf(
		(pointer.x - visible_card.position.x) / 36.0,
		-1.0,
		1.0
	)
	var shared_rotation := pointer_offset * 0.028 * stack_hover_amount
	var shared_lift := Vector2(0.0, -6.0 * stack_hover_amount)
	var shared_scale: float = _card_scale * (1.0 + 0.045 * stack_hover_amount)

	for index in cards.size():
		var card := cards[index]
		if index < reveal_step:
			card.position = _damp_vector(card.position, target_positions[index], 12.0, delta)
			card.rotation = _damp(card.rotation, target_rotations[index], 12.0, delta)
			card.scale = Vector2.ONE * _damp(card.scale.x, _card_scale, 14.0, delta)
			continue

		card.position = _damp_vector(card.position, target_positions[index] + shared_lift, 14.0, delta)
		card.rotation = _damp(card.rotation, shared_rotation, 14.0, delta)
		card.scale = Vector2.ONE * _damp(card.scale.x, shared_scale, 14.0, delta)


func _advance_stack() -> void:
	stack_hover_amount = 0.0
	card_presented.emit(reveal_step + 1)

	if cards.size() == 3 and reveal_step == 0:
		target_positions[0] = SPREAD_POSITIONS[0]
		target_rotations[0] = SPREAD_ROTATIONS[0]
		target_positions[1] = Vector2.ZERO
		target_positions[2] = Vector2(-2.0, 2.0)
		reveal_step = 1
		return

	target_positions = SPREAD_POSITIONS.duplicate()
	target_rotations = SPREAD_ROTATIONS.duplicate()
	if cards.size() == 2:
		target_positions = [Vector2(49.0, 0.0), Vector2(-49.0, 0.0)]
	elif cards.size() == 1:
		target_positions = [Vector2.ZERO]
		target_rotations = [0.0]
	mode = CardMode.SPREAD
	for card in cards:
		card.scale = Vector2.ONE * _card_scale


func _update_spread_cards(delta: float) -> void:
	var hovered_card := _find_top_card(_pointer_position())
	for index in cards.size():
		var card := cards[index]
		if card == dragged_card:
			card.scale = Vector2.ONE * _damp(card.scale.x, _card_scale * 1.06, 16.0, delta)
			continue

		card.position = _damp_vector(card.position, target_positions[index], 12.0, delta)
		card.rotation = _damp(card.rotation, target_rotations[index], 12.0, delta)
		var desired_scale: float = _card_scale * (1.035 if card == hovered_card else 1.0)
		card.scale = Vector2.ONE * _damp(card.scale.x, desired_scale, 14.0, delta)


func _begin_drag(card: Sprite2D, pointer: Vector2) -> void:
	dragged_card = card
	drag_offset = pointer - card.position
	card.z_index = next_front_z
	next_front_z += 1


func _end_drag() -> void:
	var index := cards.find(dragged_card)
	target_positions[index] = dragged_card.position
	target_rotations[index] = 0.0
	dragged_card = null
	card_dropped.emit()


func _find_top_card(pointer: Vector2) -> Sprite2D:
	var result: Sprite2D
	var highest_z := -100000
	for card in cards:
		if card.z_index > highest_z and _contains_point(card, pointer):
			result = card
			highest_z = card.z_index
	return result


func _contains_point(card: Sprite2D, pointer: Vector2) -> bool:
	return card.get_rect().has_point(card.to_local(to_global(pointer)))


func _pointer_position() -> Vector2:
	return get_local_mouse_position()


func _clamp_card_position(desired_position: Vector2) -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_size: Vector2 = (_half_size * scale).min(viewport_size * 0.5)
	var viewport_transform: Transform2D = get_global_transform_with_canvas()
	var desired_viewport: Vector2 = (viewport_transform * desired_position).clamp(half_size, viewport_size - half_size)
	return viewport_transform.affine_inverse() * desired_viewport


func _damp(current: float, target: float, speed: float, delta: float) -> float:
	return target + (current - target) * exp(-speed * delta)


func _damp_vector(current: Vector2, target: Vector2, speed: float, delta: float) -> Vector2:
	return target + (current - target) * exp(-speed * delta)
