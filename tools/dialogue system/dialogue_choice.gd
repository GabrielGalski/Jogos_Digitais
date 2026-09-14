class_name DialogueChoice
extends Resource

const NEXT_LINE: int = -1
const END_DIALOGUE: int = -2

@export var text: String = ""
@export var next_line_index: int = NEXT_LINE
@export var event_name: StringName = &""
@export var event_payload: Dictionary = {}
