extends SceneTree
## Check the LDtk placement and exercise a test-only trader through the level adapter.

const WORLD: String = "res://scenes/maps/open_world.tscn"
const OUT: String = "res://output/card_trader/"

var checks: int = 0
var failures: Array[String] = []
var world: Node2D
var player: Player
var trader: Node2D
var machine: AnimatedSprite2D
var controller: Node
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("CARD_TRADER: " + message)


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func key(code: Key, echo: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		event.echo = echo if pressed else false
		root.push_input(event, true)
	await process_frame


func click(button: Button) -> void:
	var at: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func place(point: Vector2) -> void:
	player.global_position = point - Vector2(0, 3)
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.snap_floor_height()
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()


func wait_state(value: StringName) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while trader.get("state") != value and Time.get_ticks_msec() < deadline:
		await process_frame
	check(trader.get("state") == value, "Machine reaches " + String(value))


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "Saved " + label)


func _run() -> void:
	Engine.max_fps = 60
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
	check(bool(world.get("entry_complete")), "World entry completes")
	var adapter: Node2D = world.get_node("CardTraders") as Node2D
	check(adapter.get_child_count() == 0, "No trader placed beside the central altar")
	player = world.get_node("Nox") as Player
	adapter.call("build", [{"entityInstances": [{
		"__identifier": "CardTrader", "px": [1952, 1872], "width": 48, "height": 48
	}]}], player, Callable(world, "_terrain_and_warp_height"))
	check(adapter.get_child_count() == 1, "The LDtk adapter still builds a positioned trader")
	if adapter.get_child_count() != 1:
		quit(1)
		return
	trader = adapter.get_child(0) as Node2D
	machine = trader.get_node("Visuals/Machine") as AnimatedSprite2D
	player.contact_invulnerability = 1000.0
	controller = player.get_node("GameplayKit/Manifestations")
	var action: Sprite2D = trader.get_node("ActionPrompt") as Sprite2D
	check(trader.global_position == Vector2(1952, 1872), "Fixture uses the authored feet position")
	check(machine.sprite_frames.get_frame_count(&"opening") == 5, "Uses all five supplied opening frames")
	check(machine.sprite_frames.get_animation_loop(&"opened"), "Opened animation loops")
	for index: int in range(4):
		check(machine.sprite_frames.get_frame_texture(&"closing", index) == machine.sprite_frames.get_frame_texture(&"opened", 3 - index), "Closing reverses the supplied opened frames")
	check(is_equal_approx(machine.global_scale.x, 0.75), "Native pixels displayed at the chosen gameplay size")
	check((trader.get_node("Body/CollisionShape2D") as CollisionShape2D).shape != null, "Cabinet has a solid base")
	place(trader.global_position + Vector2(92, 12))
	await ticks(4)
	await key(KEY_BACKSPACE)
	check(not paused and world.get_node_or_null("EquipmentMenu") == null, "Backspace no longer opens equipment")
	await key(KEY_E)
	check(trader.get("state") == &"machine" and not action.visible, "Distant E cannot open the machine")
	place(trader.global_position + Vector2(36, 16))
	await ticks(4)
	check(action.visible and bool(trader.call("can_interact")), "Nearby player sees native E prompt")
	check(machine.animation == &"machine" and not machine.is_playing(), "Approach leaves the machine static")
	await capture("01-machine")
	await key(KEY_E, true)
	check(trader.get("state") == &"machine", "Keyboard repeat cannot start an interaction")
	var at: Vector2 = player.global_position
	var health: float = player.health
	await key(KEY_E)
	check(trader.get("state") == &"opening" and paused and not action.visible, "E starts opening and freezes simulation")
	await key(KEY_TAB)
	check(current_scene == world, "Scene navigation waits until the interaction is over")
	await wait_state(&"opened")
	var menu: CanvasLayer = world.get_node_or_null("EquipmentMenu") as CanvasLayer
	check(menu != null and paused, "Existing equipment menu opens after the animation")
	if menu == null:
		world.queue_free()
		await ticks(2)
		quit(1)
		return
	var frames_seen: Dictionary[int, bool] = {}
	for sample: int in range(7):
		frames_seen[machine.frame] = true
		await ticks(5)
	check(frames_seen.size() >= 3 and machine.is_playing(), "Opened animation continues while menu pauses the world")
	await click(menu.get("manifestation_slot") as Button)
	await ticks(4)
	var models: Dictionary = menu.get("model_buttons") as Dictionary
	check(models.size() == 6, "Existing six selectable cards are retained")
	await click(models[5] as Button)
	check((controller.call("selected_model") as ProceduralManifestationModel).code() == &"M08", "GUI equips the selected manifestation")
	check(player.global_position == at and player.health == health, "Position and health stay frozen throughout interaction")
	await capture("02-equipment")
	await key(KEY_BACKSPACE)
	await ticks(2)
	check(trader.get("state") == &"closing" and paused and machine.animation == &"closing", "Menu exit plays opened in reverse before resuming")
	await capture("03-closing")
	await wait_state(&"machine")
	check(not paused and not machine.is_playing() and machine.animation == &"machine", "Final reverse frame restores static machine and gameplay")
	check(get_first_node_in_group(&"card_table_modal") == null, "Interaction releases its modal state")
	check((controller.call("selected_model") as ProceduralManifestationModel).code() == &"M08", "Equipped card survives closing")
	await capture("04-idle-after-trade")
	await key(KEY_E)
	await wait_state(&"opened")
	menu = world.get_node_or_null("EquipmentMenu") as CanvasLayer
	check(menu != null and world.find_children("EquipmentMenu", "", true, false).size() == 1, "Machine can reopen without duplicate menus")
	await key(KEY_ESCAPE)
	await wait_state(&"machine")
	check(not paused, "Escape closes and restores simulation")
	place(trader.global_position + Vector2(0, -18))
	await ticks(2)
	check(trader.z_index > player.z_index, "Cabinet occludes the player behind its base")
	place(trader.global_position + Vector2(0, 18))
	await ticks(2)
	check(trader.z_index < player.z_index, "Player in front remains visible")
	if rendered:
		var portal: Node2D = world.get_node("FinalPortal") as Node2D
		place(portal.global_position + Vector2(96, -48))
		await ticks(5)
		await capture("05-final-portal-path")
		for totem: Node2D in world.get_node("HordePedestals").get("pedestals"):
			if (totem.get("data") as Dictionary).get("EncounterId") == "room_2_castle_east":
				place(totem.global_position + Vector2(64, -8))
				await ticks(5)
				await capture("06-east-totem-path")
		place(trader.global_position + Vector2(0, 18))
		await ticks(2)
	# The scene may be removed during a paused interaction by a host or test runner.
	await key(KEY_E)
	await wait_state(&"opened")
	world.queue_free()
	await ticks(3)
	check(not paused, "Removing the scene during interaction releases its pause")
	var report: Dictionary = {"ok": failures.is_empty(), "checks": checks, "failures": failures}
	var file: FileAccess = FileAccess.open(OUT + "regression.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CARD_TRADER ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
