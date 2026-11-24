extends SceneTree
## Verify the authored totem scale, terrain projection and activation at all six sites.

const WORLD: String = "res://scenes/maps/open_world.tscn"
var failures: Array[String] = []
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


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


func place(player: Player, feet: Vector2) -> void:
	player.global_position = feet - Vector2(0, 3)
	player.snap_floor_height()
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()


func _run() -> void:
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
		root.content_scale_size = Vector2i(480, 270)
	var world: Node2D = (load(WORLD) as PackedScene).instantiate() as Node2D
	world.set("warp_entry_cutscene_enabled", false)
	root.add_child(world)
	current_scene = world
	var deadline: int = Time.get_ticks_msec() + 8000
	while not bool(world.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(world.get("entry_complete")), "World finishes entering")
	var player: Player = world.get_node("Nox") as Player
	player.contact_invulnerability = 1000.0
	var pedestals: Array = world.get_node("HordePedestals").get("pedestals") as Array
	check(pedestals.size() == 6, "All six authored world altars remain")
	check(world.has_node("InsectZones") and world.has_node("SlimeZones") and world.has_node("FlyingSkullZones"), "Normal enemy systems remain installed")
	key(KEY_F7, true)
	key(KEY_F7, false)
	await ticks(2)
	check(current_scene == world, "Removed F7 preview cannot replace the world")
	if rendered:
		var first_altar: Node2D = pedestals[0] as Node2D
		place(player, first_altar.global_position + Vector2(0, 64))
		await ticks(3)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://output/altar_scale_final")
		check(root.get_texture().get_image().save_png("res://output/altar_scale_final/world_totem.png") == OK, "World capture saves")
	for pedestal: Node2D in pedestals:
		var opener: Node2D = pedestal.get_node("BoosterOpener") as Node2D
		var body: AnimatedSprite2D = opener.get_node("Visuals/Surface") as AnimatedSprite2D
		var image: Image = body.sprite_frames.get_frame_texture(&"closed", 0).get_image()
		if image.is_compressed():
			image.decompress()
		check(is_equal_approx(float(image.get_used_rect().size.x) * body.global_scale.x, 39.375), "Stone altar uses the approved body width")
		place(player, pedestal.global_position + Vector2(88, 0))
		await ticks(2)
		check(not bool(pedestal.call("can_activate")), "Distant totem cannot be activated")
		place(player, pedestal.global_position + Vector2(40, 0))
		await ticks(2)
		var ground: float = float(world.call("_terrain_and_warp_height", player.to_global(Vector2(0, 3))))
		check(is_equal_approx(player.floor_height, ground), "Totem stands at the authored terrain elevation")
		check((pedestal.get_node("ActionPrompt") as Sprite2D).visible, "Each nearby totem offers E")
		key(KEY_E, true)
		key(KEY_E, false)
		await ticks(2)
		var encounter: Node2D = pedestal.get("encounter") as Node2D
		check(int(encounter.get("phase")) == 1, "Each totem starts its associated horde")
		encounter.call("skip_to_completion")
		await ticks(2)
		check(bool(opener.get("interaction_enabled")) and not bool(pedestal.call("can_activate")), "Clearing unlocks proximity opening")
	world.queue_free()
	await ticks(3)
	print("OPEN_WORLD_PEDESTAL_SCALE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " | failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
