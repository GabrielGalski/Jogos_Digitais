extends CanvasLayer
## Shared three-card equipment screen for every gameplay kit.

const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const FONT: Font = preload("res://assets/font/determination.ttf")
const THEME: Theme = preload("res://resources/visual/pack_opening_theme.tres")
const DESIGN_SIZE: Vector2 = Vector2(960.0, 540.0)

var _aspect: int = 0
var _slot_faces: Array[CardFace] = []
var _slot_names: Array[Label] = []
var _remove: Button
var controller: Node
var cards: Array[CardFace] = []
var model_buttons: Dictionary[int, Button] = {}
var manifestation_slot: Button
var _stage: Control
var _slots: HBoxContainer
var _picker: VBoxContainer
var _card_row: HBoxContainer
var _title: Label
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
		if key.keycode in [KEY_I, KEY_BACKSPACE] or key.physical_keycode in [KEY_I, KEY_BACKSPACE]:
			queue_free()
		elif key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			if _picker.visible:
				_show_slots()
			else:
				queue_free()
	get_viewport().set_input_as_handled()


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
		var slot: Button = _button("", show_aspect.bind(index))
		slot.custom_minimum_size = Vector2(224.0, 310.0)
		slot.name = ["ManifestationSlot", "InfusionSlot", "MutationSlot"][index]
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
		var aspect: Label = _label(CardFace.ASPECT_NAMES[index], 20)
		aspect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(aspect)
		var center: CenterContainer = CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(center)
		var area: Control = Control.new()
		area.custom_minimum_size = Vector2(120.0, 220.0)
		area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(area)
		var card: CardFace = CardFace.new()
		card.position = area.custom_minimum_size * 0.5
		card.scale = Vector2.ONE * (area.custom_minimum_size.x / CardFace.ART_BOUNDS.size.x)
		area.add_child(card)
		_slot_faces.append(card)
		var caption: Label = _label("", 15)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(caption)
		_slot_names.append(caption)
		if index == 0:
			manifestation_slot = slot

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
	_remove = _button("Remover carta", _choose.bind(-1))
	_remove.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_picker.add_child(_remove)
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
	show_aspect(0)


func show_aspect(aspect: int) -> void:
	_aspect = aspect
	_remove.visible = aspect != 0
	_slots.hide()
	_picker.show()
	_title.text = CardFace.ASPECT_NAMES[aspect]
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
	var definitions: Array[CardDefinition] = []
	if _aspect == 0:
		for model: ProceduralManifestationModel in controller.call("available_models"):
			definitions.append(model.card)
	elif _aspect == 1:
		definitions.assign(CATALOG.INFUSIONS)
	else:
		definitions.assign(CATALOG.MUTATIONS)
	var gap: float = float(_card_row.get_theme_constant("separation"))
	var card_width: float = minf(136.0, (_picker.custom_minimum_size.x - gap * float(definitions.size() - 1)) / float(maxi(definitions.size(), 1)))
	var rewards: Node = get_node("/root/BoosterRewards")
	for index: int in definitions.size():
		var definition: CardDefinition = definitions[index]
		var button: Button = _button("", _choose.bind(index))
		button.tooltip_text = "%s\n%s\nObtidas em boosters: %d" % [
			definition.display_name, definition.description, rewards.call("count", definition.card_id)]
		button.custom_minimum_size = Vector2(card_width, 240.0)
		button.toggle_mode = true
		for state: String in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		_card_row.add_child(button)
		model_buttons[index] = button
		var card: CardFace = CardFace.new()
		button.add_child(card)
		card.configure(definition)
		cards.append(card)
		var selected_marker: ColorRect = ColorRect.new()
		selected_marker.name = "SelectedMarker"
		selected_marker.position = Vector2((card_width - 48.0) * 0.5, 232.0)
		selected_marker.size = Vector2(48.0, 2.0)
		selected_marker.color = Color("#f4dca0")
		selected_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(selected_marker)
	_refresh_selection()


func _choose(index: int) -> void:
	if bool(controller.call(["select_model", "select_infusion", "select_mutation"][_aspect], index)):
		_refresh_slot()
		_refresh_selection()


func _refresh_slot() -> void:
	var runtime: CardCombatRuntime = (controller.get("gun") as Node).get("card_runtime") as CardCombatRuntime
	var loadout: CardLoadout = runtime.copy_loadout()
	var definitions: Array[CardDefinition] = [loadout.manifestation, loadout.infusion, loadout.mutation]
	for index: int in range(3):
		var definition: CardDefinition = definitions[index]
		var face: CardFace = _slot_faces[index]
		face.visible = definition != null
		if definition != null:
			face.configure(definition)
		_slot_names[index].text = "Vazio" if definition == null else ""
		_slot_names[index].visible = not _slot_names[index].text.is_empty()


func _refresh_selection() -> void:
	var selected: int = int(controller.get("selected_index"))
	if _aspect != 0:
		var runtime: CardCombatRuntime = (controller.get("gun") as Node).get("card_runtime") as CardCombatRuntime
		var loadout: CardLoadout = runtime.copy_loadout()
		var definition: CardDefinition = loadout.infusion as CardDefinition if _aspect == 1 else loadout.mutation as CardDefinition
		selected = int(definition.get("effect")) if definition != null else -1
	for index: int in model_buttons.keys():
		var chosen: bool = index == selected
		var button: Button = model_buttons[index]
		button.button_pressed = chosen
		(button.get_node("SelectedMarker") as ColorRect).visible = chosen
		var card: CardFace = cards[index]
		var width: float = button.custom_minimum_size.x
		card.position = Vector2(width * 0.5, 100.0 if chosen else 108.0)
		card.scale = Vector2.ONE * ((width - 10.0) / CardFace.ART_BOUNDS.size.x) * (1.035 if chosen else 1.0)
