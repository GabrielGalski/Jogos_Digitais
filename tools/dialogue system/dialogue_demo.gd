extends Control

@onready var dialogue_box: DialogueBox = $DialogueBox
@onready var status_label: Label = $DemoMargin/Info/Status

var _demo_sequence: DialogueSequence
var _can_restart: bool = false


func _ready() -> void:
	_demo_sequence = _build_demo_sequence()
	dialogue_box.dialogue_event_requested.connect(_on_dialogue_event_requested)
	dialogue_box.dialogue_finished.connect(_on_dialogue_finished)
	dialogue_box.start_dialogue(_demo_sequence)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_restart or not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_E or key_event.physical_keycode == KEY_E):
		_can_restart = false
		status_label.text = "DEMONSTRACAO DO SISTEMA"
		dialogue_box.start_dialogue(_demo_sequence)
		get_viewport().set_input_as_handled()


func _build_demo_sequence() -> DialogueSequence:
	var nox: DialogueSpeaker = DialogueSpeaker.new()
	nox.display_name = "NOX"
	nox.name_color = Color("f5d976")

	var asterion: DialogueSpeaker = DialogueSpeaker.new()
	asterion.display_name = "ASTERION"
	asterion.name_color = Color("f5d976")

	var introduction: DialogueLine = DialogueLine.new()
	introduction.speaker = asterion
	introduction.text = "Ei! Essa escada termina nos meus dominios. Voce se perdeu ou tem algum problema?"

	var nox_answer: DialogueLine = DialogueLine.new()
	nox_answer.speaker = nox
	nox_answer.text = "[wave amp=20 freq=4]⌁◌⋏◊∿  ∿⊙⋮⌁  ◌  ◍  ◎[/wave]"
	nox_answer.characters_per_second = 22.0

	var interpretation: DialogueLine = DialogueLine.new()
	interpretation.speaker = asterion
	interpretation.text = "Voce quer [shake rate=18 level=6]me derrotar[/shake], levar minhas cartas e montar a maior colecao de Monster Booster?"
	interpretation.event_name = &"ambition_revealed"

	var first_choice: DialogueChoice = DialogueChoice.new()
	first_choice.text = "Quero suas cartas."
	first_choice.next_line_index = 4
	first_choice.event_name = &"cards_demanded"

	var second_choice: DialogueChoice = DialogueChoice.new()
	second_choice.text = "Vim conhecer a arena."
	second_choice.next_line_index = 5
	second_choice.event_name = &"arena_questioned"

	var question: DialogueLine = DialogueLine.new()
	question.speaker = asterion
	question.text = "Entao diga, monstrinho. O que voce veio buscar?"
	question.choices = [first_choice, second_choice]

	var cards_result: DialogueLine = DialogueLine.new()
	cards_result.speaker = asterion
	cards_result.text = "[shake rate=22 level=8]MINOTAUROS![/shake] Protejam minha colecao!"
	cards_result.next_line_index = DialogueLine.END_DIALOGUE
	cards_result.event_name = &"minotaurs_called"

	var arena_result: DialogueLine = DialogueLine.new()
	arena_result.speaker = asterion
	arena_result.text = "Ha! Pelo menos voce reconhece uma arena digna do grande Asterion."
	arena_result.next_line_index = DialogueLine.END_DIALOGUE

	var sequence: DialogueSequence = DialogueSequence.new()
	sequence.sequence_id = &"dialogue_system_demo"
	sequence.lines = [introduction, nox_answer, interpretation, question, cards_result, arena_result]
	return sequence


func _on_dialogue_event_requested(event_name: StringName, _payload: Dictionary) -> void:
	status_label.text = "EVENTO DA FALA: " + String(event_name).to_upper()


func _on_dialogue_finished(_sequence_id: StringName) -> void:
	status_label.text = "DIALOGO CONCLUIDO — E PARA REINICIAR"
	_can_restart = true
