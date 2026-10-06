extends Node

const ARENA: PackedScene = preload("res://scenes/tutorial_arena.tscn")
const BOSS_SCRIPT: Script = preload("res://scripts/asterion_skybreaker.gd")
var failures: int = 0
var jump_count: int = 0
var encounters: int = 0
var capture_enabled: bool = false

func _ready() -> void:
	capture_enabled = DisplayServer.get_name() != "headless"
	var arena: Node2D = ARENA.instantiate() as Node2D
	var boss: Variant = arena.get_node("MinotaurChair")
	boss.skybreaker_started.connect(func() -> void: jump_count += 1)
	boss.encounter_started.connect(func() -> void: encounters += 1)
	add_child(arena)
	var player: Player = arena.get_node("Mox") as Player
	var dialogue: DialogueBox = boss.get_node("IntroDialogue") as DialogueBox
	for tick: int in range(400):
		await get_tree().physics_frame
		if arena.get("entrance_complete"):
			break
	_check(bool(arena.get("entrance_complete")), "Entrance completes")
	_check(not player.intro_locked, "Exploration is unlocked after stairs")
	_check(not dialogue.is_dialogue_active(), "No conversation at spawn")
	await _tap(KEY_SPACE)
	_check(jump_count == 0, "Space cannot start the encounter remotely")
	_key(KEY_W, true)
	for tick: int in range(500):
		await get_tree().physics_frame
		if bool(boss.intro_started):
			break
	_key(KEY_W, false)
	_check(encounters == 1, "Walking towards the throne triggers encounter once")
	for tick: int in range(500):
		await get_tree().physics_frame
		if dialogue.is_dialogue_active():
			break
	_check(dialogue.is_dialogue_active(), "Automatic approach leads to dialogue")
	_check(player.position.distance_to(boss.intro_destination) < 0.1, "Nox stops at existing approach destination")
	_check(player.intro_locked, "Movement locked for dialogue")
	var locked_position: Vector2 = player.position
	_key(KEY_S, true)
	_key(KEY_SPACE, true)
	for tick: int in range(150):
		await get_tree().physics_frame
	_key(KEY_S, false)
	_key(KEY_SPACE, false)
	_check(player.position.distance_to(locked_position) < 0.1, "WASD cannot move Nox during conversation")
	_check(jump_count == 0, "Waiting/space cannot bypass conversation")
	_check(boss.get_node("Asterion").animation == &"sitting", "Asterion stays seated throughout dialogue")
	var line_count: int = boss.intro_dialogue.lines.size()
	for index: int in range(line_count):
		_check(dialogue.current_line_index() == index, "Conversation order %d" % index)
		var expected: DialogueLine = boss.intro_dialogue.lines[index]
		_check(dialogue.name_label.text == expected.speaker.display_name, "Speaker name %d" % index)
		if dialogue.is_revealing_text():
			await _tap(KEY_E)
			_check(dialogue.current_line_index() == index, "First E only reveals text %d" % index)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(dialogue.body_text.get_content_height() <= dialogue.body_text.size.y + 1.0, "Full text fits at line %d" % index)
		if index in [0, 1, 5, 10]:
			await _capture("line_%02d" % index)
		_check(jump_count == 0, "No jump before last confirmation %d" % index)
		await _tap(KEY_E)
	_check(not dialogue.is_dialogue_active(), "Last E closes box")
	_check(jump_count == 0, "Last E reveals the weapon before the horde")
	_check(player.intro_locked, "Reveal keeps movement locked")
	_check(player.get_node("BoosterShooter").equipped, "Nox equips the weapon")
	print("[INTRO DIALOGUE] %d failures; %d lines; %d jumps; %d encounter" % [failures, line_count, jump_count, encounters])
	get_tree().quit(0 if failures == 0 else 1)

func _tap(code: Key) -> void:
	_key(code, true)
	await get_tree().process_frame
	_key(code, false)
	await get_tree().process_frame

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("[INTRO DIALOGUE] " + message)

func _capture(label: String) -> void:
	if not capture_enabled:
		return
	await RenderingServer.frame_post_draw
	var capture_image: Image = get_viewport().get_texture().get_image()
	capture_image.save_png("res://tmp/asterion_dialogue_" + label + ".png")

