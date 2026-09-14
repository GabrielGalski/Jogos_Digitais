class_name DialogueLine
extends Resource

const NEXT_LINE: int = -1
const END_DIALOGUE: int = -2

@export var speaker: DialogueSpeaker
@export_multiline var text: String = ""
@export_range(4.0, 120.0, 1.0) var characters_per_second: float = 34.0
@export var next_line_index: int = NEXT_LINE
@export var choices: Array[DialogueChoice] = []
@export var event_name: StringName = &""
@export var event_payload: Dictionary = {}
