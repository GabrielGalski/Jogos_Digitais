extends CanvasLayer
## A paused, reversible tabletop overlay. Coordinates use a fitted 960x540 stage.

signal closed

const DESIGN_SIZE: Vector2 = Vector2(960.0, 540.0)
const WORLD_PATH: String = "res://scenes/maps/open_world.tscn"
const FONT: Font = preload("res://assets/font/determination.ttf")
const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const GROUP_FOLDERS: Array[String] = ["manifestacao", "infusao", "mutacao"]
const GROUP_NAMES: Array[String] = ["Manifestação", "Infusão", "Mutação"]
const GROUP_CENTERS: Array[float] = [180.0, 480.0, 780.0]
const DRAG_THRESHOLD: float = 6.0

var cards: Array[CardTableCard] = []
var selected_card: CardTableCard = null
var _stage: Control
var _dimmer: ColorRect
var _hint: Label
var _deal_button: Button
var _pile_labels: Array[Label] = []
var _piles: Array[Array] = [[], [], []]
var _pressed_card: CardTableCard = null
var _pointer: Vector2 = Vector2(-1000.0, -1000.0)
var _press_position: Vector2 = Vector2.ZERO
var _drag_offset: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _focus_position: Vector2 = DESIGN_SIZE * 0.5
var _was_paused: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_HIDDEN
var _world_visual: CanvasItem = null
var _world_was_visible: bool = true


func _ready() -> void:
	add_to_group(&"card_table_modal")
	_was_paused = get_tree().paused
	get_tree().paused = true
	_world_visual = get_parent() as CanvasItem
	if _world_visual != null:
		_world_was_visible = _world_visual.visible
		_world_visual.hide()
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var cursor: CanvasLayer = get_node_or_null("/root/GameCursor") as CanvasLayer
	if cursor != null:
		cursor.hide()
	_build_table()
	_load_cards()
	_fit_stage()
	get_viewport().size_changed.connect(_fit_stage)
	_update_labels()


func _exit_tree() -> void:
	if is_instance_valid(_world_visual):
		_world_visual.visible = _world_was_visible
	get_tree().paused = _was_paused
	Input.mouse_mode = _previous_mouse_mode
	var cursor: CanvasLayer = get_node_or_null("/root/GameCursor") as CanvasLayer
	if cursor != null:
		cursor.show()


func close_table() -> void:
	closed.emit()
	queue_free()


func _build_table() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("#100e16")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_stage = Control.new()
	_stage.name = "TableStage"
	_stage.size = DESIGN_SIZE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	var felt: ColorRect = ColorRect.new()
	felt.size = DESIGN_SIZE
	felt.color = Color("#2b202f")
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(felt)
	var mat: Panel = Panel.new()
	mat.position = Vector2(16.0, 72.0)
	mat.size = Vector2(928.0, 432.0)
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("#211b29")
	style.set_border_width_all(1)
	style.border_color = Color("#44344c")
	mat.add_theme_stylebox_override("panel", style)
	_stage.add_child(mat)
	var hud: MarginContainer = MarginContainer.new()
	hud.size = DESIGN_SIZE
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		hud.add_theme_constant_override("margin_" + side, 24 if side != "bottom" else 10)
	_stage.add_child(hud)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	hud.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.custom_minimum_size.y = 28.0
	column.add_child(heading)
	var title: Label = _label("Mesa de cartas", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button: Button = _button("Voltar [Enter]", close_table)
	heading.add_child(close_button)
	var groups: HBoxContainer = HBoxContainer.new()
	groups.add_theme_constant_override("separation", 0)
	column.add_child(groups)
	for group: String in GROUP_NAMES:
		var label: Label = _label(group, 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		groups.add_child(label)
		_pile_labels.append(label)
	var space: Control = Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(space)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	column.add_child(footer)
	_hint = _label("Clique na pilha para retirar uma carta · Arraste para mover", 14)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_hint)
	_deal_button = _button("Desempilhar todas", deal_all)
	footer.add_child(_deal_button)
	_dimmer = ColorRect.new()
	_dimmer.size = DESIGN_SIZE
	_dimmer.color = Color(0.025, 0.015, 0.035, 0.0)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dimmer.z_index = 1000
	_stage.add_child(_dimmer)


func _label(value: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#e9efec"))
	return label


func _button(value: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = value
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 14)
	for state: String in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("#503b59") if state != "normal" else Color("#35283f")
		style.border_color = Color("#917a9d")
		style.set_border_width_all(1)
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		style.content_margin_top = 6.0
		style.content_margin_bottom = 6.0
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	return button


func _load_cards() -> void:
	var geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/card_art_layout.json")) as Dictionary
	var bounds: Array = geometry["visible_rect"] as Array
	var visible_rect: Rect2 = Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3]))
	var finishes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/card_table_finishes.json")) as Dictionary
	var finish_cards: Dictionary = finishes["cards"] as Dictionary
	var paths: Dictionary[StringName, String] = CATALOG.art_paths()
	var definitions: Dictionary[StringName, CardDefinition] = {}
	for definition: CardDefinition in CATALOG.implemented_cards():
		definitions[CATALOG.alias(definition)] = definition
	for group: int in GROUP_FOLDERS.size():
		var ordered: Array[String] = []
		for id: StringName in paths:
			if paths[id].begins_with("res://assets/cards/" + GROUP_FOLDERS[group] + "/"):
				ordered.append(String(id))
		for id: StringName in definitions:
			if definitions[id].get_kind() == group and not paths.has(id):
				ordered.append(String(id))
		ordered.sort()
		for index: int in ordered.size():
			var id: String = ordered[index]
			var card: CardTableCard = CardTableCard.new()
			var key: StringName = StringName(id)
			var use_live: bool = id in ["M06", "M08", "U03", "I11"] or not paths.has(key)
			var texture: Texture2D = null if use_live else load(paths[key]) as Texture2D
			var finish: Dictionary = finish_cards.get(id, {}) as Dictionary
			var tint: Color = Color(str(finish["tint"])) if finish.has("tint") else Color.TRANSPARENT
			if use_live:
				var face: CardFace = CardFace.new()
				face.configure(definitions[key])
				card.configure(null, id, group, index, CardFace.ART_BOUNDS)
				card.use_live_face(face, CardFace.ART_BOUNDS.size)
			else:
				card.configure(texture, id, group, index, visible_rect, tint)
			card.name = card.card_id
			card.target_position = Vector2(GROUP_CENTERS[group], 264.0) + Vector2(-2.0, 2.0) * float(index)
			card.position = card.target_position + Vector2(0.0, 24.0)
			card.z_index = 500 - index
			_stage.add_child(card)
			cards.append(card)
			_piles[group].append(card)


func _fit_stage() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	_stage.scale = Vector2.ONE * factor
	_stage.position = (viewport_size - DESIGN_SIZE * factor) * 0.5


func _process(delta: float) -> void:
	var blend: float = 1.0 - exp(-14.0 * delta)
	_dimmer.color.a = lerpf(_dimmer.color.a, 0.76 if selected_card != null else 0.0, blend)
	var hovered: CardTableCard = _pick_card(_pointer)
	for card: CardTableCard in cards:
		if card == selected_card:
			var pointer_ratio: Vector2 = ((_pointer - card.position) / card.focus_size * 2.0).clamp(-Vector2.ONE, Vector2.ONE)
			var inside: bool = card.contains_point(_pointer)
			card.target_tilt = Vector2(-pointer_ratio.y * 0.10, pointer_ratio.x * 0.12) if inside else Vector2.ZERO
			card.target_position = _focus_position + pointer_ratio * 2.0 if inside and not _dragging else _focus_position
			continue
		if card.on_table:
			card.target_size = card.normal_size * (1.035 if card == hovered and not _dragging else 1.0)
			if not _dragging or card != _pressed_card:
				card.target_position = card.table_position + Vector2(0.0, -3.0 if card == hovered else 0.0)
				card.target_angle = card.table_angle
		else:
			var depth: int = _piles[card.aspect].find(card)
			card.target_position = Vector2(GROUP_CENTERS[card.aspect], 264.0) + Vector2(-2.0, 2.0) * float(depth)
			if hovered != null and not hovered.on_table and hovered.aspect == card.aspect:
				card.target_position.y -= 5.0


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
				if selected_card != null:
					return_selected()
				else:
					close_table()
			elif key.keycode in [KEY_ENTER, KEY_KP_ENTER] or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
				close_table()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_pointer = _stage.get_global_transform_with_canvas().affine_inverse() * (event as InputEventMouseMotion).position
		_move_pointer()
		if _pressed_card != null or selected_card != null:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		_pointer = _stage.get_global_transform_with_canvas().affine_inverse() * mouse.position
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_pressed_card = _pick_card(_pointer)
				_press_position = _pointer
				_dragging = false
				if _pressed_card != null:
					_drag_offset = _pressed_card.position - _pointer
			else:
				_release_pointer()
			if _pressed_card != null or selected_card != null or _dragging:
				get_viewport().set_input_as_handled()


func _move_pointer() -> void:
	if _pressed_card == null:
		return
	if not _dragging and _pointer.distance_to(_press_position) > DRAG_THRESHOLD:
		_dragging = true
		if selected_card == null:
			if not _pressed_card.on_table:
				_deal_card(_pressed_card)
			_bring_forward(_pressed_card)
	if not _dragging:
		return
	if selected_card != null:
		_focus_position = _clamp_position(_pointer + _drag_offset, selected_card.focus_size)
		selected_card.position = _focus_position
		selected_card.target_position = _focus_position
	else:
		_pressed_card.table_position = _clamp_position(_pointer + _drag_offset, _pressed_card.normal_size)
		_pressed_card.position = _pressed_card.table_position
		_pressed_card.target_position = _pressed_card.table_position


func _release_pointer() -> void:
	if _pressed_card != null:
		if not _dragging:
			if selected_card != null:
				return_selected()
			elif _pressed_card.on_table:
				inspect_card(_pressed_card)
			else:
				_deal_card(_pressed_card)
	_pressed_card = null
	_dragging = false


func _pick_card(pointer: Vector2) -> CardTableCard:
	if selected_card != null:
		return selected_card if selected_card.contains_point(pointer) else null
	var picked: CardTableCard = null
	for card: CardTableCard in cards:
		if not card.on_table and (_piles[card.aspect].is_empty() or _piles[card.aspect][0] != card):
			continue
		if card.contains_point(pointer) and (picked == null or card.z_index > picked.z_index or (card.z_index == picked.z_index and card.get_index() > picked.get_index())):
			picked = card
	return picked


func _deal_card(card: CardTableCard) -> void:
	if card.on_table:
		return
	card.on_table = true
	_piles[card.aspect].erase(card)
	var total: int = 0
	for candidate: CardTableCard in cards:
		if candidate.aspect == card.aspect:
			total += 1
	var row: int = floori(float(card.order) / 3.0)
	var row_count: int = mini(3, total - row * 3)
	card.table_position = Vector2(GROUP_CENTERS[card.aspect] + (float(card.order % 3) - float(row_count - 1) * 0.5) * 94.0, 154.0 + float(row) * 140.0)
	card.table_angle = 0.0
	card.target_position = card.table_position
	card.target_angle = card.table_angle
	_bring_forward(card)
	_update_labels()


func deal_all() -> void:
	if selected_card != null:
		return
	for card: CardTableCard in cards:
		_deal_card(card)


func inspect_card(card: CardTableCard) -> void:
	if selected_card != null or not card.on_table:
		return
	selected_card = card
	_focus_position = DESIGN_SIZE * 0.5
	card.target_position = _focus_position
	card.target_angle = 0.0
	card.target_size = card.focus_size
	card.z_index = 2000
	card.set_inspected(true)
	_hint.text = "Arraste para mover · Passe o mouse nas bordas · Clique para devolver"


func return_selected() -> void:
	if selected_card == null:
		return
	var card: CardTableCard = selected_card
	selected_card = null
	_pressed_card = null
	_dragging = false
	card.target_position = card.table_position
	card.target_angle = card.table_angle
	card.target_size = card.normal_size
	card.set_inspected(false)
	_bring_forward(card)
	_update_labels()


func _bring_forward(card: CardTableCard) -> void:
	card.z_index = 20
	_stage.move_child(card, _stage.get_child_count() - 1)


func _clamp_position(point: Vector2, card_size: Vector2) -> Vector2:
	var half: Vector2 = card_size * 0.5 + Vector2(8.0, 8.0)
	return point.clamp(Vector2(24.0, 76.0) + half, Vector2(936.0, 504.0) - half)


func _update_labels() -> void:
	var remaining: int = 0
	for group: int in _piles.size():
		remaining += _piles[group].size()
		_pile_labels[group].text = GROUP_NAMES[group] + " · " + str(_piles[group].size()) + " na pilha"
	_deal_button.visible = remaining > 0
	_hint.text = "Clique na pilha para retirar uma carta · Arraste para mover" if remaining > 0 else "Arraste pela mesa · Clique numa carta para examinar"
