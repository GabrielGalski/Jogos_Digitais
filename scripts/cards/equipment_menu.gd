extends CanvasLayer
## Shared paused equipment screen for every gameplay kit. Only manifestations are editable.

const FONT: Font = preload("res://assets/font/determination.ttf")
const THEME: Theme = preload("res://resources/visual/pack_opening_theme.tres")
const DESIGN_SIZE: Vector2 = Vector2(960.0, 540.0)

var controller: Node
var cards: Array[CardTableCard] = []
var model_buttons: Dictionary[int, Button] = {}
var manifestation_slot: Button
var _stage: Control
var _slots: HBoxContainer
var _picker: VBoxContainer
var _card_row: HBoxContainer
var _slot_image: TextureRect
var _slot_name: Label
var _title: Label
var _geometry: Rect2
var _finishes: Dictionary = {}
var _art_paths: Dictionary[StringName, String] = {}
var _previous_pause: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_HIDDEN
var _world: CanvasItem = null
var _world_visible: bool = true


func _ready() -> void:
	add_to_group(&"card_table_modal")
	_previous_pause = get_tree().paused
	get_tree().paused = true
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var cursor: CanvasLayer = get_node_or_null("/root/GameCursor") as CanvasLayer
	if cursor != null:
		cursor.hide()
	_world = get_tree().current_scene as CanvasItem
	if _world != null:
		_world_visible = _world.visible
		_world.hide()
	_read_art()
	_build()
	_refresh_slot()
	_fit()
	get_viewport().size_changed.connect(_fit)


func _exit_tree() -> void:
	if is_instance_valid(_world):
		_world.visible = _world_visible
	get_tree().paused = _previous_pause
	Input.mouse_mode = _previous_mouse_mode
	var cursor: CanvasLayer = get_node_or_null("/root/GameCursor") as CanvasLayer
	if cursor != null:
		cursor.show()
	if is_instance_valid(controller):
		controller.call("suspend_trigger")


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	if key.pressed and not key.echo:
		if key.keycode == KEY_BACKSPACE or key.physical_keycode == KEY_BACKSPACE:
			queue_free()
		elif key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			if _picker.visible:
				_show_slots()
			else:
				queue_free()
	get_viewport().set_input_as_handled()


func _read_art() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/card_art_layout.json")) as Dictionary
	var bounds: Array = layout["visible_rect"] as Array
	_geometry = Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3]))
	var finishes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cards/card_table_finishes.json")) as Dictionary
	_finishes = finishes["cards"] as Dictionary
	var folder: String = "res://assets/cards/manifestacao"
	for directory: String in DirAccess.get_directories_at(folder):
		var path: String = folder + "/" + directory + "/" + directory + ".png"
		if ResourceLoader.exists(path):
			_art_paths[StringName(directory.get_slice(" ", 1))] = path


func _build() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("#211b29")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_stage = Control.new()
	_stage.name = "EquipmentStage"
	_stage.size = DESIGN_SIZE
	_stage.theme = THEME
	_stage.add_theme_font_override("font", FONT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	var margin: MarginContainer = MarginContainer.new()
	margin.size = DESIGN_SIZE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	_stage.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	column.add_child(header)
	_title = _label("Equipamento", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(_button("Fechar", queue_free))
	var body: CenterContainer = CenterContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", 48)
	body.add_child(_slots)
	for index: int in 3:
		var slot: Button = _button("", show_manifestations if index == 0 else Callable())
		slot.custom_minimum_size = Vector2(224.0, 310.0)
		slot.disabled = index != 0
		_slots.add_child(slot)
		var inset: MarginContainer = MarginContainer.new()
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["left", "right", "top", "bottom"]:
			inset.add_theme_constant_override("margin_" + side, 14)
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(inset)
		var content: VBoxContainer = VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 8)
		inset.add_child(content)
		var aspect: Label = _label(["Manifestação", "Infusão", "Mutação"][index], 20)
		aspect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(aspect)
		if index == 0:
			manifestation_slot = slot
			slot.name = "ManifestationSlot"
			_slot_image = TextureRect.new()
			_slot_image.custom_minimum_size = Vector2(128.0, 198.0)
			_slot_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_slot_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_slot_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			_slot_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(_slot_image)
			_slot_name = _label("", 15)
			_slot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			content.add_child(_slot_name)
	_picker = VBoxContainer.new()
	_picker.name = "ManifestationPicker"
	_picker.custom_minimum_size.x = 880.0
	_picker.add_theme_constant_override("separation", 14)
	_picker.hide()
	body.add_child(_picker)
	_card_row = HBoxContainer.new()
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.add_theme_constant_override("separation", 12)
	_picker.add_child(_card_row)
	var back: Button = _button("Voltar", _show_slots)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_picker.add_child(back)


func _label(value: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(value: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 15)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if action.is_valid():
		button.pressed.connect(action)
	return button


func _fit() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	_stage.scale = Vector2.ONE * factor
	_stage.position = (viewport_size - DESIGN_SIZE * factor) * 0.5


func show_manifestations() -> void:
	_slots.hide()
	_picker.show()
	_title.text = "Manifestação"
	_build_cards()


func _show_slots() -> void:
	_picker.hide()
	_slots.show()
	_title.text = "Equipamento"
	_refresh_slot()


func _build_cards() -> void:
	for child: Node in _card_row.get_children():
		_card_row.remove_child(child)
		child.queue_free()
	cards.clear()
	model_buttons.clear()
	var models: Array[ProceduralManifestationModel] = controller.call("available_models") as Array[ProceduralManifestationModel]
	for index: int in models.size():
		var model: ProceduralManifestationModel = models[index] as ProceduralManifestationModel
		var button: Button = _button("", _choose.bind(index))
		button.custom_minimum_size = Vector2(136.0, 240.0)
		button.toggle_mode = true
		for state: String in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		_card_row.add_child(button)
		model_buttons[index] = button
		var card: CardTableCard = CardTableCard.new()
		var finish: Dictionary = _finishes.get(String(model.code()), {}) as Dictionary
		var tint: Color = Color(str(finish["tint"])) if finish.has("tint") else Color.TRANSPARENT
		card.configure(load(_art_paths[model.code()]) as Texture2D, String(model.code()), 0, 0, _geometry, tint)
		card.normal_size = Vector2(120.0, 120.0 * _geometry.size.y / _geometry.size.x)
		card.target_size = card.normal_size
		card.position = Vector2(68.0, 108.0)
		card.target_position = card.position
		button.add_child(card)
		cards.append(card)
		var selected_marker: ColorRect = ColorRect.new()
		selected_marker.name = "SelectedMarker"
		selected_marker.position = Vector2(44.0, 232.0)
		selected_marker.size = Vector2(48.0, 2.0)
		selected_marker.color = Color("#f4dca0")
		selected_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(selected_marker)
		if model.code() == &"M08":
			var caption: Label = _label(model.card.display_name, 14)
			caption.position = Vector2(0.0, 204.0)
			caption.size = Vector2(136.0, 22.0)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.add_child(caption)
	_refresh_selection()


func _choose(index: int) -> void:
	if bool(controller.call("select_model", index)):
		_refresh_slot()
		_refresh_selection()


func _refresh_slot() -> void:
	var model: ProceduralManifestationModel = controller.call("selected_model") as ProceduralManifestationModel
	_slot_image.texture = load(_art_paths[model.code()]) as Texture2D
	_slot_name.text = model.card.display_name if model.code() == &"M08" else ""
	_slot_name.visible = model.code() == &"M08"


func _refresh_selection() -> void:
	for index: int in model_buttons.keys():
		var chosen: bool = index == int(controller.get("selected_index"))
		var button: Button = model_buttons[index]
		button.button_pressed = chosen
		(button.get_node("SelectedMarker") as ColorRect).visible = chosen
		var card: CardTableCard = cards[index]
		card.target_position = Vector2(68.0, 100.0 if chosen else 108.0)
		card.target_size = card.normal_size * (1.035 if chosen else 1.0)


func _process(_delta: float) -> void:
	if not _picker.visible:
		return
	for card: CardTableCard in cards:
		var button: Button = card.get_parent() as Button
		var relative: Vector2 = (card.get_local_mouse_position() / card.normal_size * 2.0).clamp(-Vector2.ONE, Vector2.ONE)
		card.target_tilt = Vector2(-relative.y, relative.x) * 0.045 if button.is_hovered() else Vector2.ZERO
