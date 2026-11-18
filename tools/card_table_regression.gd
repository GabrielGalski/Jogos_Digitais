extends SceneTree
## Exercises the normal map keyboard entry and pointer click/drag distinction.

var failures: int = 0
var checks: int = 0
var table: CanvasLayer
var stage: Control
var pointer: Vector2 = Vector2.ZERO
var rendered: bool = false


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CARD TABLE: " + message)


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _move(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = stage.get_global_transform_with_canvas() * point
	event.relative = event.position - pointer
	pointer = event.position
	root.push_input(event, true)
	await process_frame


func _button(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = pointer
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame


func _click(point: Vector2) -> void:
	await _move(point)
	await _button(true)
	await _button(false)


func _drag(from: Vector2, to: Vector2) -> void:
	await _move(from)
	await _button(true)
	for step: int in range(1, 9):
		await _move(from.lerp(to, float(step) / 8.0))
	await _button(false)


func _capture(name: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/cards/table/" + name + ".png")


func _check_border_pixels(card: CardTableCard) -> void:
	if not rendered:
		return
	var face: Polygon2D = card.get("_face") as Polygon2D
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(208, 320)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = face.texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.position = Vector2(104.0, 160.0)
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline: Image = viewport.get_texture().get_image()
	sprite.material = face.material
	await process_frame
	await RenderingServer.frame_post_draw
	var effect: Image = viewport.get_texture().get_image()
	var mask: Image = CardTableCard.BORDER_MASK.get_image()
	var changed_center: int = 0
	var changed_border: int = 0
	for y: int in 320:
		for x: int in 208:
			if not baseline.get_pixel(x, y).is_equal_approx(effect.get_pixel(x, y)):
				if mask.get_pixel(x, y).r > 0.5:
					changed_border += 1
				else:
					changed_center += 1
	check(changed_border > 500, card.card_id + " has a visible holographic border")
	check(changed_center == 0, card.card_id + " foil leaves every unmasked pixel unchanged")
	effect.save_png("res://output/cards/table/border_" + card.card_id + "_native.png")
	print("BORDER PIXELS %s: changed border=%d; changed center=%d" % [card.card_id, changed_border, changed_center])
	viewport.queue_free()


func _run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	Engine.max_fps = 60
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/maps/open_world.tscn")
	await process_frame
	await process_frame
	var map: Node2D = current_scene as Node2D
	if map == null:
		check(false, "The main map loaded")
		quit(1)
		return
	var timeout: int = 0
	while not bool(map.get("entry_complete")) and timeout < 600:
		await process_frame
		timeout += 1
	check(bool(map.get("entry_complete")), "World entry completed")
	var player: Node2D = map.get_node("Nox") as Node2D
	var saved_position: Vector2 = player.position
	var saved_health: float = float(player.get("health"))
	await _key(KEY_ENTER)
	table = map.get_node_or_null("CardTable") as CanvasLayer
	check(table != null, "Enter on the main map opens the actual card scene")
	if table == null:
		quit(1)
		return
	stage = table.get("_stage") as Control
	await create_timer(0.7).timeout
	var cards: Array[CardTableCard] = table.get("cards")
	check(cards.size() == 19, "The 18 authored cards and explicit temporary M08 are present")
	var correct_geometry: bool = true
	var correct_finishes: bool = true
	var special_count: int = 0
	var special_cards: Array[CardTableCard] = []
	var finishes: Dictionary = {"M04": Color("#b678ff"), "I04": Color("#65e6a0"), "U04": Color("#f4c45c")}
	for card: CardTableCard in cards:
		var face: Polygon2D = card.get("_face") as Polygon2D
		correct_geometry = correct_geometry and face.texture.get_size() == Vector2(208.0, 320.0)
		correct_geometry = correct_geometry and face.uv[0] == Vector2(2.0, 2.0) and face.uv[2] == Vector2(206.0, 318.0)
		if finishes.has(card.card_id):
			special_count += 1
			special_cards.append(card)
			correct_finishes = correct_finishes and card.foil_tint == finishes[card.card_id] and face.material != null
		else:
			correct_finishes = correct_finishes and face.material == null
	check(correct_geometry, "All cards use the native 208x320 texture and source-derived crop")
	check(correct_finishes and special_count == 3, "Only the three documented candidates have purple, green and gold foil")
	var piles: Array[Array] = table.get("_piles")
	check(piles[0].size() == 8 and piles[1].size() == 5 and piles[2].size() == 6, "Three piles contain 8 / 5 / 6 cards")
	check(paused, "World is paused while the table is open")
	await _capture("01_stacks")
	await _key(KEY_TAB)
	check(current_scene == map and is_instance_valid(table), "Tab cannot jump away from the modal")
	var first: CardTableCard = piles[0][0] as CardTableCard
	await _click(first.position)
	check(first.on_table and piles[0].size() == 7, "A click deals exactly one card")
	check(table.get("selected_card") == null, "Dealing does not immediately inspect")
	var second: CardTableCard = piles[0][0] as CardTableCard
	await _drag(second.position, Vector2(390.0, 395.0))
	check(second.on_table and second.table_position.distance_to(Vector2(390.0, 395.0)) < 1.0, "A card can be dragged straight from the stack")
	check(table.get("selected_card") == null, "A drag does not trigger click inspection")
	var deal_button: Button = table.get("_deal_button") as Button
	var center: Vector2 = stage.get_global_transform().affine_inverse() * deal_button.get_global_rect().get_center()
	await _click(center)
	check(piles[0].is_empty() and piles[1].is_empty() and piles[2].is_empty(), "The deal-all button empties all three piles")
	await create_timer(0.6).timeout
	await _capture("02_spread")
	await _drag(first.position, Vector2(480.0, 265.0))
	check(first.table_position.distance_to(Vector2(480.0, 265.0)) < 1.0, "Dealt cards move freely over the table")
	check(table.call("_pick_card", first.position) == first, "The most recently dragged overlapping card is on top")
	var original_drop: Vector2 = first.table_position
	await _click(first.position)
	check(table.get("selected_card") == first, "Press and release without dragging inspects the card")
	await create_timer(0.5).timeout
	check(first.target_angle == 0.0 and first.target_size == first.focus_size, "Inspection raises and straightens the card")
	var dimmer: ColorRect = table.get("_dimmer") as ColorRect
	check(dimmer.color.a > 0.7 and first.z_index > dimmer.z_index, "Background dims below the selected card")
	await _move(Vector2(575.0, 150.0))
	await create_timer(0.25).timeout
	check(first.current_tilt.length() > 0.04 and first.current_tilt.length() < 0.17, "Card edges cause a small smooth perspective tilt")
	await _capture("03_inspect")
	await _drag(first.position, Vector2(610.0, 290.0))
	check(table.get("selected_card") == first, "The inspected card can be dragged without returning")
	await _click(first.position)
	await create_timer(0.5).timeout
	check(table.get("selected_card") == null, "The next click returns it to the table")
	check(first.target_position.distance_to(original_drop) < 4.0, "The original table placement is restored")
	check(player.position == saved_position and float(player.get("health")) == saved_health, "The paused world keeps position and health")
	for card: CardTableCard in special_cards:
		await _click(card.position)
		check(table.get("selected_card") == card, "The candidate " + card.card_id + " is accessible on the table")
		await create_timer(0.4).timeout
		await _move(Vector2(565.0, 155.0))
		await create_timer(0.2).timeout
		await _capture("finish_" + card.card_id)
		await _check_border_pixels(card)
		table.call("return_selected")
		await create_timer(0.4).timeout
	await _key(KEY_ENTER)
	await process_frame
	check(map.get_node_or_null("CardTable") == null and not paused, "Enter closes the table and resumes the same map")
	await _key(KEY_ENTER)
	check(map.get_node_or_null("CardTable") != null, "The preview can be reopened")
	await _key(KEY_ESCAPE)
	await process_frame
	check(map.get_node_or_null("CardTable") == null and not paused, "Escape closes and restores pause state")
	print("CARD TABLE REGRESSION: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	if failures == 0 and "--keep-open" in OS.get_cmdline_user_args():
		await _key(KEY_ENTER)
		return
	quit(0 if failures == 0 else 1)
