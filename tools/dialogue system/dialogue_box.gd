class_name DialogueBox
extends CanvasLayer

signal dialogue_started(sequence_id: StringName)
signal line_started(line_index: int, line: DialogueLine)
signal character_revealed(character: String)
signal dialogue_event_requested(event_name: StringName, payload: Dictionary)
signal choice_selected(line_index: int, choice_index: int, choice: DialogueChoice)
signal dialogue_finished(sequence_id: StringName)

const END_DIALOGUE: int = -2
const NEXT_LINE: int = -1
const DEFAULT_TEXT_COLOR: Color = Color("f6edf4")
const DEFAULT_NAME_COLOR: Color = Color("f5d976")
const CHOICE_COLOR: Color = Color("f6edf4")
const CHOICE_SELECTED_COLOR: Color = Color("f5d976")
const COMMA_PAUSE: float = 0.12
const SENTENCE_PAUSE: float = 0.24

@export var advance_physical_key: Key = KEY_E
@export var voice_interval_characters: int = 2
@export var punctuation_pauses_enabled: bool = true

@onready var interface_root: Control = $Interface
@onready var portrait_column: Control = $Interface/SafeArea/Layout/DialogueRow/PortraitColumn
@onready var portrait_texture: TextureRect = $Interface/SafeArea/Layout/DialogueRow/PortraitColumn/PortraitOuter/PortraitBlack/PortraitInner/Portrait
@onready var dialogue_column: VBoxContainer = $Interface/SafeArea/Layout/DialogueRow/DialogueColumn
@onready var name_outer: PanelContainer = $Interface/SafeArea/Layout/DialogueRow/DialogueColumn/NameOuter
@onready var name_label: Label = $Interface/SafeArea/Layout/DialogueRow/DialogueColumn/NameOuter/NameBlack/NameInner/NameMargin/Name
@onready var body_text: RichTextLabel = $Interface/SafeArea/Layout/DialogueRow/DialogueColumn/BodyOuter/BodyBlack/BodyInner/BodyMargin/Content/Text
@onready var choices_container: VBoxContainer = $Interface/SafeArea/Layout/DialogueRow/DialogueColumn/BodyOuter/BodyBlack/BodyInner/BodyMargin/Content/Choices
@onready var continue_outer: PanelContainer = $Interface/SafeArea/Layout/DialogueRow/DialogueColumn/BodyOuter/BodyBlack/BodyInner/BodyMargin/Content/ContinueRow/ContinueOuter
@onready var voice_player: AudioStreamPlayer = $Voice

var _sequence: DialogueSequence
var _line: DialogueLine
var _line_index: int = -1
var _plain_text: String = ""
var _revealing: bool = false
var _awaiting_choice: bool = false
var _selected_choice: int = 0
var _character_accumulator: float = 0.0
var _punctuation_pause_remaining: float = 0.0
var _voice_character_counter: int = 0
var _choice_labels: Array[Label] = []


func _ready() -> void:
	interface_root.hide()
	set_process(false)


func start_dialogue(sequence: DialogueSequence, from_line_index: int = -1) -> void:
	if sequence == null or sequence.lines.is_empty():
		push_warning("DialogueBox received an empty dialogue sequence.")
		return
	_sequence = sequence
	var requested_index: int = sequence.start_line_index if from_line_index < 0 else from_line_index
	if requested_index < 0 or requested_index >= sequence.lines.size():
		push_warning("DialogueBox received an invalid starting line index.")
		return
	interface_root.show()
	set_process(true)
	dialogue_started.emit(_sequence.sequence_id)
	_show_line(requested_index)


func is_dialogue_active() -> bool:
	return interface_root.visible and _sequence != null


func is_revealing_text() -> bool:
	return _revealing


func current_line_index() -> int:
	return _line_index


func reveal_current_line() -> void:
	if not _revealing:
		return
	body_text.visible_characters = _plain_text.length()
	_finish_reveal()


func advance() -> void:
	if not is_dialogue_active():
		return
	if _revealing:
		reveal_current_line()
		return
	if _awaiting_choice:
		_confirm_choice()
		return
	_advance_from_line(_line.next_line_index)


func close_dialogue() -> void:
	_finish_dialogue()


func _process(delta: float) -> void:
	if not _revealing or _line == null:
		return
	if _punctuation_pause_remaining > 0.0:
		_punctuation_pause_remaining = maxf(0.0, _punctuation_pause_remaining - delta)
		return
	_character_accumulator += delta * _line.characters_per_second
	while _character_accumulator >= 1.0 and body_text.visible_characters < _plain_text.length():
		_character_accumulator -= 1.0
		_reveal_next_character()
		if _punctuation_pause_remaining > 0.0:
			break
	if body_text.visible_characters >= _plain_text.length():
		_finish_reveal()


func _unhandled_input(event: InputEvent) -> void:
	if not is_dialogue_active() or not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var handled: bool = false
	if key_event.physical_keycode == advance_physical_key or key_event.keycode == advance_physical_key:
		advance()
		handled = true
	elif _awaiting_choice and _is_up_key(key_event):
		_move_choice(-1)
		handled = true
	elif _awaiting_choice and _is_down_key(key_event):
		_move_choice(1)
		handled = true
	if handled:
		get_viewport().set_input_as_handled()


func _show_line(index: int) -> void:
	if _sequence == null or index < 0 or index >= _sequence.lines.size():
		_finish_dialogue()
		return
	_clear_choices()
	_line_index = index
	_line = _sequence.lines[index]
	if _line == null:
		push_warning("DialogueBox skipped a null line resource.")
		_advance_from_line(NEXT_LINE)
		return
	_apply_speaker(_line.speaker)
	body_text.text = _line.text
	_plain_text = body_text.get_parsed_text()
	body_text.visible_characters = 0
	_character_accumulator = 0.0
	_punctuation_pause_remaining = 0.0
	_voice_character_counter = 0
	_revealing = not _plain_text.is_empty()
	_awaiting_choice = false
	continue_outer.hide()
	line_started.emit(_line_index, _line)
	if not _revealing:
		_finish_reveal()


func _apply_speaker(speaker: DialogueSpeaker) -> void:
	if speaker == null:
		name_outer.hide()
		portrait_column.hide()
		body_text.add_theme_color_override("default_color", DEFAULT_TEXT_COLOR)
		voice_player.stream = null
		return
	name_label.text = speaker.display_name
	name_label.add_theme_color_override("font_color", speaker.name_color if speaker.name_color.a > 0.0 else DEFAULT_NAME_COLOR)
	name_outer.visible = not speaker.display_name.is_empty()
	body_text.add_theme_color_override("default_color", speaker.text_color if speaker.text_color.a > 0.0 else DEFAULT_TEXT_COLOR)
	portrait_texture.texture = speaker.portrait
	portrait_column.visible = speaker.portrait != null
	dialogue_column.size_flags_stretch_ratio = 1.0
	voice_player.stream = speaker.voice


func _reveal_next_character() -> void:
	var visible_index: int = body_text.visible_characters
	if visible_index < 0 or visible_index >= _plain_text.length():
		return
	var character: String = _plain_text.substr(visible_index, 1)
	body_text.visible_characters = visible_index + 1
	character_revealed.emit(character)
	if not character.strip_edges().is_empty():
		_voice_character_counter += 1
		if voice_player.stream != null and _voice_character_counter >= maxi(1, voice_interval_characters):
			_voice_character_counter = 0
			voice_player.play()
	if punctuation_pauses_enabled:
		if character in [",", ";", ":"]:
			_punctuation_pause_remaining = COMMA_PAUSE
		elif character in [".", "!", "?"]:
			_punctuation_pause_remaining = SENTENCE_PAUSE


func _finish_reveal() -> void:
	_revealing = false
	body_text.visible_characters = _plain_text.length()
	if not _line.choices.is_empty():
		_show_choices()
	else:
		continue_outer.show()


func _show_choices() -> void:
	_awaiting_choice = true
	_selected_choice = 0
	choices_container.show()
	for choice: DialogueChoice in _line.choices:
		if choice == null:
			continue
		var label: Label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		choices_container.add_child(label)
		_choice_labels.append(label)
	if _choice_labels.is_empty():
		_awaiting_choice = false
		continue_outer.show()
		return
	_refresh_choices()


func _move_choice(direction: int) -> void:
	if _choice_labels.is_empty():
		return
	_selected_choice = wrapi(_selected_choice + direction, 0, _choice_labels.size())
	_refresh_choices()


func _refresh_choices() -> void:
	for index: int in range(_choice_labels.size()):
		var label: Label = _choice_labels[index]
		var choice: DialogueChoice = _line.choices[index]
		label.text = ("> " if index == _selected_choice else "  ") + choice.text
		label.add_theme_color_override("font_color", CHOICE_SELECTED_COLOR if index == _selected_choice else CHOICE_COLOR)


func _confirm_choice() -> void:
	if _choice_labels.is_empty() or _selected_choice >= _line.choices.size():
		return
	var choice: DialogueChoice = _line.choices[_selected_choice]
	choice_selected.emit(_line_index, _selected_choice, choice)
	if not choice.event_name.is_empty():
		dialogue_event_requested.emit(choice.event_name, choice.event_payload.duplicate(true))
	_awaiting_choice = false
	_advance_from_line(choice.next_line_index)


func _advance_from_line(next_index: int) -> void:
	_emit_line_event()
	if next_index == END_DIALOGUE:
		_finish_dialogue()
		return
	var resolved_index: int = _line_index + 1 if next_index == NEXT_LINE else next_index
	if _sequence == null or resolved_index < 0 or resolved_index >= _sequence.lines.size():
		_finish_dialogue()
		return
	_show_line(resolved_index)


func _emit_line_event() -> void:
	if _line != null and not _line.event_name.is_empty():
		dialogue_event_requested.emit(_line.event_name, _line.event_payload.duplicate(true))


func _clear_choices() -> void:
	for label: Label in _choice_labels:
		if is_instance_valid(label):
			label.queue_free()
	_choice_labels.clear()
	choices_container.hide()


func _finish_dialogue() -> void:
	if _sequence == null:
		interface_root.hide()
		set_process(false)
		return
	var finished_id: StringName = _sequence.sequence_id
	_clear_choices()
	_revealing = false
	_awaiting_choice = false
	_line = null
	_line_index = -1
	_sequence = null
	interface_root.hide()
	set_process(false)
	dialogue_finished.emit(finished_id)


func _is_up_key(event: InputEventKey) -> bool:
	return event.keycode in [KEY_UP, KEY_W] or event.physical_keycode in [KEY_UP, KEY_W]


func _is_down_key(event: InputEventKey) -> bool:
	return event.keycode in [KEY_DOWN, KEY_S] or event.physical_keycode in [KEY_DOWN, KEY_S]
