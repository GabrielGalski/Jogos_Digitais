extends Control
## Lesson input stays available while the tutorial is paused.
signal dismiss_requested

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode == KEY_E or key_event.keycode == KEY_E:
		# Consume E before unpausing so it cannot also advance a dialogue.
		get_viewport().set_input_as_handled()
		dismiss_requested.emit()
