extends SceneTree
## The OS pointer stays hidden while each scene has exactly one visible in-game pointer.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(480, 270)
	var cursor: CanvasLayer = root.get_node_or_null("GameCursor") as CanvasLayer
	_check(cursor != null, "Global in-game cursor was not loaded")
	if cursor == null:
		_finish()
		return
	var pointer: Sprite2D = cursor.get_node("GamePointer") as Sprite2D
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "Windows cursor is not hidden")
	change_scene_to_file("res://scenes/merchant_corridor.tscn")
	await process_frame
	await process_frame
	await process_frame
	_check(pointer.visible and pointer.texture != null, "Merchant hall has no visible replacement pointer")
	change_scene_to_file("res://scenes/dungeon/merchant_platform.tscn")
	await process_frame
	await process_frame
	await process_frame
	_check(not pointer.visible, "Combat room duplicated the local reticle")
	_check((current_scene.get_node("CombatUI/Crosshair") as Sprite2D).visible, "Combat room reticle was hidden")
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	await process_frame
	_check(not pointer.visible, "Tutorial duplicated its local reticle")
	_check(current_scene.find_child("Crosshair", true, false) != null, "Tutorial reticle is missing")
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "Windows cursor reappeared after scene changes")
	_finish()


func _finish() -> void:
	print("GAME CURSOR: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
