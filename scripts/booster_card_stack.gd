extends Node2D
class_name BoosterCardStack

const CARD_SCALE := 1.34
const CARD_HIT_RECT := Rect2(Vector2(-27.0, -35.0), Vector2(54.0, 71.0))
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

@onready var cards: Array[Sprite2D] = [$Card1, $Card2, $Card3]

var mode := CardMode.HIDDEN
var reveal_elapsed := 0.0
var reveal_step := 0
var stack_hover_amount := 0.0
var target_positions: Array[Vector2] = STACK_POSITIONS.duplicate()
var target_rotations: Array[float] = [0.0, 0.0, 0.0]
var dragged_card: Sprite2D
var drag_offset := Vector2.ZERO
var next_front_z := 10


func _ready() -> void:
	reset_cards()


func begin_reveal() -> void:
	visible = true
	mode = CardMode.REVEALING
	reveal_elapsed = 0.0
	reveal_step = 0
	stack_hover_amount = 0.0
	dragged_card = null
	target_positions = STACK_POSITIONS.duplicate()
	target_rotations = [0.0, 0.0, 0.0]
	set_process(true)

	for index in cards.size():
		var card := cards[index]
		card.position = STACK_POSITIONS[index] + Vector2(0.0, 8.0)
		card.rotation = 0.0
		card.scale = Vector2.ONE * CARD_SCALE
		card.modulate.a = 0.0
		card.z_index = 3 - index


func finish_reveal() -> void:
	mode = CardMode.STACKED
	reveal_step = 0
	stack_hover_amount = 0.0
	for index in cards.size():
		cards[index].position = STACK_POSITIONS[index]
		cards[index].modulate.a = 1.0


func reset_cards() -> void:
	mode = CardMode.HIDDEN
	visible = false
	dragged_card = null
	reveal_elapsed = 0.0
	reveal_step = 0
	stack_hover_amount = 0.0
	next_front_z = 10
	set_process(false)

	for index in cards.size():
		var card := cards[index]
		card.position = STACK_POSITIONS[index]
		card.rotation = 0.0
		card.scale = Vector2.ONE * CARD_SCALE
		card.modulate.a = 1.0
		card.z_index = 3 - index


func _process(delta: float) -> void:
	if mode == CardMode.REVEALING:
		_update_reveal(delta)
	elif mode == CardMode.STACKED:
		_update_stack(delta)
	elif mode == CardMode.SPREAD:
		_update_spread_cards(delta)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if mode == CardMode.STACKED and _contains_point(cards[reveal_step], _pointer_position()):
				_advance_stack()
				get_viewport().set_input_as_handled()
			elif mode == CardMode.SPREAD:
				var selected_card := _find_top_card(_pointer_position())
				if selected_card:
					_begin_drag(selected_card)
					get_viewport().set_input_as_handled()
		elif dragged_card:
			_end_drag()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and dragged_card:
		var desired_position := _pointer_position() - drag_offset
		dragged_card.position = _clamp_card_position(desired_position)
		var index := cards.find(dragged_card)
		target_positions[index] = dragged_card.position
		dragged_card.rotation = clampf(event.relative.x * 0.012, -0.16, 0.16)
		get_viewport().set_input_as_handled()


func _update_reveal(delta: float) -> void:
	reveal_elapsed += delta
	var progress := smoothstep(0.0, 0.28, reveal_elapsed)
	for index in cards.size():
		var card := cards[index]
		card.position = STACK_POSITIONS[index] + Vector2(0.0, (1.0 - progress) * 8.0)
		card.modulate.a = progress


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
	var shared_scale := CARD_SCALE * (1.0 + 0.045 * stack_hover_amount)

	for index in cards.size():
		var card := cards[index]
		if index < reveal_step:
			card.position = _damp_vector(card.position, target_positions[index], 12.0, delta)
			card.rotation = _damp(card.rotation, target_rotations[index], 12.0, delta)
			card.scale = Vector2.ONE * _damp(card.scale.x, CARD_SCALE, 14.0, delta)
			continue

		card.position = _damp_vector(card.position, target_positions[index] + shared_lift, 14.0, delta)
		card.rotation = _damp(card.rotation, shared_rotation, 14.0, delta)
		card.scale = Vector2.ONE * _damp(card.scale.x, shared_scale, 14.0, delta)


func _advance_stack() -> void:
	stack_hover_amount = 0.0

	if reveal_step == 0:
		# Primeiro clique: a carta verde vai para a direita e revela a azul.
		target_positions[0] = SPREAD_POSITIONS[0]
		target_rotations[0] = SPREAD_ROTATIONS[0]
		target_positions[1] = Vector2.ZERO
		target_positions[2] = Vector2(-2.0, 2.0)
		reveal_step = 1
		return

	# Segundo clique: a azul vai para a esquerda e a vermelha permanece ao centro.
	target_positions = SPREAD_POSITIONS.duplicate()
	target_rotations = SPREAD_ROTATIONS.duplicate()
	mode = CardMode.SPREAD
	for card in cards:
		card.scale = Vector2.ONE * CARD_SCALE


func _update_spread_cards(delta: float) -> void:
	var hovered_card := _find_top_card(_pointer_position())
	for index in cards.size():
		var card := cards[index]
		if card == dragged_card:
			card.scale = Vector2.ONE * _damp(card.scale.x, CARD_SCALE * 1.06, 16.0, delta)
			continue

		card.position = _damp_vector(card.position, target_positions[index], 12.0, delta)
		card.rotation = _damp(card.rotation, target_rotations[index], 12.0, delta)
		var desired_scale := CARD_SCALE * (1.035 if card == hovered_card else 1.0)
		card.scale = Vector2.ONE * _damp(card.scale.x, desired_scale, 14.0, delta)


func _begin_drag(card: Sprite2D) -> void:
	dragged_card = card
	drag_offset = _pointer_position() - card.position
	card.z_index = next_front_z
	next_front_z += 1


func _end_drag() -> void:
	var index := cards.find(dragged_card)
	target_positions[index] = dragged_card.position
	target_rotations[index] = 0.0
	dragged_card = null


func _find_top_card(pointer: Vector2) -> Sprite2D:
	var result: Sprite2D
	var highest_z := -100000
	for card in cards:
		if card.z_index > highest_z and _contains_point(card, pointer):
			result = card
			highest_z = card.z_index
	return result


func _contains_point(card: Sprite2D, pointer: Vector2) -> bool:
	return CARD_HIT_RECT.has_point(card.to_local(to_global(pointer)))


func _pointer_position() -> Vector2:
	return get_local_mouse_position()


func _clamp_card_position(desired_position: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var card_half_size := Vector2(28.0, 37.0) * CARD_SCALE
	var desired_global := position + desired_position
	desired_global = desired_global.clamp(card_half_size, viewport_size - card_half_size)
	return desired_global - position


func _damp(current: float, target: float, speed: float, delta: float) -> float:
	return target + (current - target) * exp(-speed * delta)


func _damp_vector(current: Vector2, target: Vector2, speed: float, delta: float) -> Vector2:
	return target + (current - target) * exp(-speed * delta)
