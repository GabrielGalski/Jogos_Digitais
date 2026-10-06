extends SceneTree
## Exercises E against the real paused tutorial, not a simulated callback.
var failures: int = 0
var dismissed: Array[StringName] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func press_key(key: Key, echo: bool = false, physical: bool = true) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key if physical else 0
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	var release: InputEventKey = event.duplicate() as InputEventKey
	release.pressed = false
	release.echo = false
	Input.parse_input_event(release)

func _on_dismissed(lesson_id: StringName) -> void:
	dismissed.append(lesson_id)

func _run() -> void:
	root.size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	var arena: Node2D = current_scene as Node2D
	var boss: Node = arena.get_node("MinotaurChair")
	boss.set("auto_start_encounter", false)
	var encounter: Node = boss.get_node("TutorialEncounter")
	var completion: Node = encounter.get("completion") as Node
	completion.connect(&"lesson_dismissed", _on_dismissed)
	var modal: Control = completion.get_node("EliteLesson") as Control
	await create_timer(2.7).timeout
	completion.call(&"show_controls_lesson")
	check(paused and modal.visible, "Controls lesson did not pause and open")
	check(modal.can_process() and not completion.can_process(), "Lesson input must work while its owner is paused")
	press_key(KEY_E, true)
	await process_frame
	check(paused and modal.visible and dismissed.is_empty(), "Repeated E dismissed a lesson")
	press_key(KEY_Q)
	await process_frame
	check(paused and modal.visible, "Unrelated key dismissed a lesson")
	press_key(KEY_E)
	await process_frame
	check(not paused and not modal.visible and dismissed == [&"controls"], "E did not dismiss controls exactly once and resume")
	completion.call(&"_show_lesson", &"elite", "ASTERION É UM ELITE")
	press_key(KEY_E, false, false)
	await process_frame
	check(not paused and not modal.visible and dismissed == [&"controls", &"elite"], "E did not dismiss Asterion explanation")
	press_key(KEY_E)
	await process_frame
	check(dismissed.size() == 2, "Hidden lesson consumed another dismissal")
	completion.call(&"_show_lesson", &"elite", "ASTERION")
	(completion.get_node("EliteLesson/Panel/Content/Ok") as Button).pressed.emit()
	check(not paused and not modal.visible and dismissed.size() == 3, "Mouse confirmation stopped working")
	print("TUTORIAL LESSON E INPUT: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
