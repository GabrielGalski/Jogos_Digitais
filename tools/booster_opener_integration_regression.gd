extends SceneTree
## Play the LDtk encounters through activation, real kills and proximity-based completion.

const WORLD: String = "res://scenes/maps/open_world.tscn"
const CLOSED: Texture2D = preload("res://assets/tiles/structures/booster_opener/closed1.png")
const VIEWER: PackedScene = preload("res://scenes/cards/booster_viewer.tscn")
const CENTIPEDE: Script = preload("res://scripts/enemies/flying_centipede.gd")
const OUT: String = "res://output/horde_totems/"

var failures: Array[String] = []
var checks: int = 0
var rendered: bool = false
var world: Node2D = null
var player: Player = null


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("BOOSTER_INTEGRATION: " + message)


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func mouse_button(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	root.push_input(event, true)


func mouse_move(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = point
	root.push_input(event, true)


func place(feet: Vector2) -> void:
	player.global_position = feet - Vector2(0, 3)
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.snap_floor_height()
	player.reset_physics_interpolation()


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "Saved " + label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	world = (load(WORLD) as PackedScene).instantiate() as Node2D
	world.set("warp_entry_cutscene_enabled", false)
	root.add_child(world)
	current_scene = world
	var deadline: int = Time.get_ticks_msec() + 12000
	while not bool(world.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(world.get("entry_complete")), "World entry finishes")
	player = world.get_node("Nox") as Player
	player.contact_invulnerability = 1000.0
	var totems: Array = world.get_node("HordePedestals").get("pedestals") as Array
	check(totems.size() == 6, "Six authored encounters")
	var source: Image = CLOSED.get_image()
	if source.is_compressed():
		source.decompress()
	var bounds: Rect2 = Rect2(source.get_used_rect())
	for totem: Node2D in totems:
		var surface: AnimatedSprite2D = totem.get_node("BoosterOpener/Visuals/Surface") as AnimatedSprite2D
		var center: Vector2 = surface.to_global(bounds.get_center() - CLOSED.get_size() * 0.5)
		var terrain_height: float = float(world.call("_terrain_and_warp_height", totem.global_position))
		check(center.distance_to(totem.global_position - Vector2(0, terrain_height)) < 0.01, "Totem centered on its terrain")
		check(is_equal_approx(surface.global_scale.x * bounds.size.x, 63.36), "World body keeps the approved scale")
		check(not totem.has_node("Plate"), "Old platform removed")
		check(totem.get("encounter") != null, "LDtk encounter ID resolves")
	var first: Node2D = totems[0] as Node2D
	var encounter: Node2D = first.get("encounter") as Node2D
	var opener: Node2D = first.get_node("BoosterOpener") as Node2D
	var idle: Node2D = opener.get_node("Visuals/ExclamationMarker") as Node2D
	var warning: Node2D = opener.get_node("Visuals/CombatWarning") as Node2D
	var warning_sprite: AnimatedSprite2D = warning.get_node("Warning") as AnimatedSprite2D
	var action: Sprite2D = first.get_node("ActionPrompt") as Sprite2D
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	place(first.global_position + Vector2(88, 0))
	await ticks(12)
	camera.reset_smoothing()
	camera.force_update_scroll()
	check(idle.visible and not warning.visible and not action.visible, "Unstarted encounter shows only the yellow exclamation")
	key(KEY_E, true)
	key(KEY_E, false)
	await ticks(3)
	check(int(encounter.get("phase")) == 0, "Distant E cannot start encounter")
	await capture("01-inativo")
	place(first.global_position + Vector2(40, 12))
	await ticks(6)
	camera.reset_smoothing()
	camera.force_update_scroll()
	check(action.visible and not idle.visible and not warning.visible, "Approach replaces exclamation with E")
	check(str(opener.get("state")) == "closed", "Approach alone does not open the machine")
	await capture("02-ativar")
	key(KEY_E, true)
	key(KEY_E, false)
	for frame: int in range(1200):
		if not (encounter.get("actors") as Array).is_empty():
			break
		await ticks(1)
	check(int(encounter.get("phase")) == 1 and not (encounter.get("actors") as Array).is_empty(), "E starts actual enemy spawns")
	check(warning.visible and not action.visible and not idle.visible, "Combat replaces E with warning")
	check(warning_sprite.sprite_frames.get_frame_count(&"idle") == 9 and warning_sprite.is_playing(), "Authored nine-frame warning loops")
	check((warning.get_node("WarningLight") as PointLight2D).enabled and not (idle.get_node("YellowLight") as PointLight2D).enabled, "Only the warning light is active")
	if rendered:
		await ticks(120)
	await capture("03-combate")
	place(first.global_position + Vector2(88, 0))
	await ticks(5)
	for frame: int in range(600):
		if is_instance_valid(encounter.get("miniboss")):
			break
		await physics_frame
	var miniboss: CENTIPEDE = encounter.get("miniboss") as CENTIPEDE
	check(is_instance_valid(miniboss), "The altar spawns the centipede before the pack can be earned")
	if not is_instance_valid(miniboss):
		quit(1)
		return
	encounter.set_physics_process(false)
	var target_count: int = int(encounter.get("kill_target"))
	for index: int in range(target_count):
		check(warning.visible and str(opener.get("state")) == "closed", "Combat warning stays up until final kill")
		var ghosts: Array = encounter.get("actors") as Array
		var ghost: Node2D = ghosts[0] as Node2D if not ghosts.is_empty() else encounter.call("_spawn_one") as Node2D
		if ghost == null:
			check(false, "Real spirit spawned for combat kill")
			break
		ghost.call("take_damage", 1000.0)
	check(int(encounter.get("phase")) == 1, "The encounter stays active until the centipede is defeated")
	for segment: Node2D in miniboss.segments.duplicate():
		segment.call("take_damage", 3.0)
	await ticks(4)
	check(int(encounter.get("phase")) == 2 and not warning.visible and not idle.visible, "Final kill ends encounter and clears markers")
	check(str(opener.get("state")) == "closed", "Distant cleared machine stays closed")
	place(first.global_position + Vector2(36, 16))
	await ticks(85)
	camera.reset_smoothing()
	camera.force_update_scroll()
	var cards: Array[Node] = opener.get_node("Visuals/Cards").get_children()
	check(str(opener.get("state")) == "opened" and cards.size() == 3, "Nearby cleared machine opens")
	for card: Sprite2D in cards:
		check(card.visible and card.modulate.a > 0.99, "All three cards are visible")
	check(not first.has_node("PackOpening") and not paused, "Proximity presents the cards without opening the pack")
	var reward_surface: AnimatedSprite2D = opener.get_node("Visuals/Surface") as AnimatedSprite2D
	var machine_point: Vector2 = reward_surface.get_global_transform_with_canvas().origin
	mouse_button(machine_point + Vector2(0, 85), true)
	mouse_button(machine_point + Vector2(0, 85), false)
	await ticks(3)
	check(not first.has_node("PackOpening"), "A ground click leaves the pack closed")
	check((opener.get_node("ActionPrompt") as Sprite2D).visible, "The cleared opener shows E when the cards are ready")
	var game_cursor: CanvasLayer = root.get_node("GameCursor") as CanvasLayer
	var previous_mouse_mode: Input.MouseMode = Input.mouse_mode
	key(KEY_E, true)
	key(KEY_E, false)
	await ticks(3)
	var viewer: BoosterViewer = first.get_node_or_null("PackOpening/BoosterViewer") as BoosterViewer
	check(viewer != null and paused and not action.visible, "E opens the pack at a nearby cleared machine")
	if viewer == null:
		quit(1)
		return
	check(not viewer.has_node("Hud") and viewer.opening_pointer.visible, "The cut guide and plus pointer replace the opening HUD")
	check(not game_cursor.visible and (not rendered or Input.mouse_mode == Input.MOUSE_MODE_HIDDEN), "Only the opening pointer is visible")
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	await ticks(3)
	check(current_scene == world and viewer.visible, "Tab cannot jump away from the booster viewer")
	var volume: int = int(first.get("_reward_volume"))
	var reward: Array[CardDefinition] = []
	reward.assign(first.get("_reward_cards"))
	check(volume >= 1 and volume <= 3 and reward.size() == 3, "Pedestal rolls one of three packs with three cards")
	var ids: Dictionary[StringName, int] = {}
	var collection: Node = root.get_node("BoosterRewards")
	for card: CardDefinition in reward:
		ids[card.card_id] = int(collection.call("count", card.card_id))
	check(ids.size() == 3, "Cards in the same pack are distinct")
	var seal: PackedVector2Array = viewer.call("_seal_points")
	var transform: Transform2D = viewer.get_global_transform_with_canvas()
	var start: Vector2 = transform * seal[0]
	var end: Vector2 = transform * seal[1]
	mouse_button(start - Vector2(10, 0), true)
	mouse_move(start.lerp(end, 0.2))
	mouse_button(start.lerp(end, 0.2), false)
	await ticks(3)
	check(viewer.booster_state == BoosterViewer.BoosterState.IDLE, "An incomplete cut leaves the pack sealed")
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await ticks(3)
	check(not paused and int(first.get("_reward_volume")) == volume, "Cancel keeps the previously rolled reward")
	check(game_cursor.visible and Input.mouse_mode == previous_mouse_mode, "Cancel restores the gameplay cursor")
	var floating_card: Sprite2D = cards[1] as Sprite2D
	var card_point: Vector2 = floating_card.get_global_transform_with_canvas().origin
	mouse_button(card_point, true)
	mouse_button(card_point, false)
	await ticks(3)
	viewer = first.get_node_or_null("PackOpening/BoosterViewer") as BoosterViewer
	check(viewer != null and paused, "Clicking a floating card resumes a dismissed opening")
	if viewer == null:
		quit(1)
		return
	var pointer_at: Vector2 = Vector2(352, 117)
	mouse_move(pointer_at)
	check(viewer.opening_pointer.position.distance_to(pointer_at) < 2.0, "The plus follows the mouse in the opening overlay")
	await capture("booster-01-lacrado")
	seal = viewer.call("_seal_points")
	transform = viewer.get_global_transform_with_canvas()
	start = transform * seal[0]
	end = transform * seal[1]
	mouse_button(start - Vector2(10, 0), true)
	mouse_move(end + Vector2(10, 0))
	mouse_button(end + Vector2(10, 0), false)
	mouse_move(pointer_at)
	await ticks(12)
	check(viewer.booster_state == BoosterViewer.BoosterState.OPENING and not viewer.pieces_released and not viewer.card_stack.visible, "A valid cut starts a shake with the cards covered")
	check(viewer.booster.position.length() > 1.0, "The sealed foil moves during the windup")
	await capture("booster-02-chacoalho")
	await ticks(26)
	var pack_y: float = viewer.booster.position.y
	var card_position: Vector2 = viewer.card_stack.cards[0].global_position
	check(viewer.booster.visible and viewer.booster.modulate.a == 1.0 and viewer.tear.modulate.a == 1.0 and pack_y > 0.0, "The foil falls fully opaque")
	check(viewer.card_stack.visible and card_position.is_equal_approx(viewer.size * 0.5), "The card is revealed at the center during the fall")
	check(viewer.booster_anchor.z_index > viewer.card_stack.z_index + viewer.card_stack.cards[0].z_index, "The descending foil uncovers the card from the front")
	await capture("booster-03-queda")
	await ticks(9)
	check(viewer.booster.position.y > pack_y and viewer.card_stack.cards[0].global_position.is_equal_approx(card_position), "The card stays at the center while the foil continues falling")
	for frame: int in range(50):
		if viewer.booster_state == BoosterViewer.BoosterState.CARDS:
			break
		await process_frame
	check(viewer.booster_state == BoosterViewer.BoosterState.CARDS and not viewer.booster.visible and viewer.call("_below_view", viewer.booster), "The foil crosses the bottom before the reveal finishes")
	check(viewer.card_stack.cards.size() == 3, "Reveal shows the three rewards")
	for card: CardDefinition in reward:
		check(int(collection.call("count", card.card_id)) == ids[card.card_id] + 1, "Each card is granted once")
	check(int(first.get("_reward_volume")) == 0, "Cut consumes the reward")
	await capture("booster-04-cartas")
	for index: int in range(2):
		var visible_card: Sprite2D = viewer.card_stack.cards[index]
		var click_at: Vector2 = visible_card.get_global_transform_with_canvas().origin
		mouse_button(click_at, true)
		mouse_button(click_at, false)
		await ticks(18)
	check(viewer.card_stack.mode == BoosterCardStack.CardMode.SPREAD, "The center stack can still be spread by clicking")
	var spread_card: Sprite2D = viewer.card_stack.cards[0]
	var drag_start: Vector2 = spread_card.get_global_transform_with_canvas().origin
	var drag_end: Vector2 = drag_start + Vector2(18, 24)
	mouse_button(drag_start, true)
	mouse_move(drag_end)
	check(viewer.card_stack.dragged_card == spread_card and viewer.opening_pointer.position.distance_to(drag_end) < 2.0, "The plus follows the mouse while dragging a card")
	mouse_button(drag_end, false)
	key(KEY_SPACE, true)
	key(KEY_SPACE, false)
	await ticks(3)
	check(not paused, "Closing the reveal unpauses gameplay")
	check(game_cursor.visible and Input.mouse_mode == previous_mouse_mode, "Closing the reveal restores the gameplay cursor")
	place(first.global_position + Vector2(110, 0))
	await ticks(85)
	check(str(opener.get("state")) == "closed", "Leaving retracts cards")
	place(first.global_position + Vector2(36, 16))
	await ticks(85)
	check(not first.has_node("PackOpening"), "Returning to a claimed pedestal does not grant another pack")
	mouse_button(reward_surface.get_global_transform_with_canvas().origin, true)
	mouse_button(reward_surface.get_global_transform_with_canvas().origin, false)
	check(not first.has_node("PackOpening"), "Clicking a claimed pedestal leaves its reward consumed")
	var second: Node2D = totems[1] as Node2D
	var other: Node2D = second.get("encounter") as Node2D
	place(second.global_position + Vector2(40, 0))
	await ticks(3)
	other.call("begin")
	check(int(other.get("phase")) == 1, "A second pedestal starts an active horde")
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	await ticks(4)
	check(current_scene == world and int(other.get("phase")) == 2 and not bool(world.get("_travel_busy")), "Active horde overrides the world scene jump")
	check(int(second.get("_reward_volume")) > 0, "Tab completion grants the same pending booster as a combat victory")
	var third: Node2D = totems[2] as Node2D
	other = third.get("encounter") as Node2D
	place(third.global_position + Vector2(40, 0))
	await ticks(3)
	other.call("begin")
	other.call("_on_player_defeated")
	await ticks(2)
	check(int(other.get("phase")) == 3 and not (third.get_node("BoosterOpener/Visuals/CombatWarning") as Node2D).visible, "Aborted encounter removes warning")
	world.queue_free()
	await ticks(3)
	for variant: int in range(1, 4):
		var pack: BoosterViewer = VIEWER.instantiate() as BoosterViewer
		root.add_child(pack)
		pack.open_pack(variant, reward)
		var size: Vector2 = pack.booster.texture.get_size()
		var corners: PackedVector2Array = pack.booster.polygon
		var cut: PackedVector2Array = pack.call("_seal_points")
		check(size == Vector2(96, 160), "Volume %d uses its authored canvas" % variant)
		check(is_equal_approx((corners[2].y - corners[1].y) / (corners[1].x - corners[0].x), size.y / size.x), "Volume %d preserves aspect ratio" % variant)
		check(cut[0].y >= pack.booster_anchor.position.y + corners[0].y and cut[0].y < pack.booster_anchor.position.y, "Volume %d guides the cut along the upper seal" % variant)
		if rendered:
			await capture("pack-vol-%d" % variant)
		var reverse: bool = variant == 2
		var from: Vector2 = cut[1] + Vector2(8, 0) if reverse else cut[0] - Vector2(8, 0)
		var to: Vector2 = cut[0] - Vector2(8, 0) if reverse else cut[1] + Vector2(8, 0)
		mouse_button(from, true)
		mouse_move(to)
		mouse_button(to, false)
		pack._process(pack.opening_profile.shake_duration + 0.18)
		check(is_instance_valid(pack.tear.texture) and pack.tear.texture.get_size() == size, "Volume %d tears its own artwork" % variant)
		var pivot: Vector2 = pack._tear_pivot * pack.current_scale
		var strip_travel: Vector2 = pack.tear.transform * pivot - pivot
		check(pack.pieces_released and pack.card_stack.visible and strip_travel.x * (-1 if reverse else 1) > 0.0, "Volume %d preserves tear direction and reveal timing" % variant)
		pack.queue_free()
		await process_frame
	var report: Dictionary = {"ok": failures.is_empty(), "checks": checks, "failures": failures}
	var report_file: FileAccess = FileAccess.open(OUT + "world-regression.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	print("HORDE_TOTEMS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
