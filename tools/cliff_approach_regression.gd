extends SceneTree
## Real player sweeps and input at the four cliff fronts, with all three ramps retained.
const WORLD: PackedScene = preload("res://scenes/maps/open_world.tscn")
const OUT: String = "res://output/cliff_approach/"
var arena: Node2D = null
var player: Player = null
var failures: Array[String] = []
var checks: int = 0
var rendered: bool = false
var report: Dictionary = {}


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(value: bool, description: String) -> void:
	checks += 1
	if value: return
	failures.append(description)
	push_error("[CLIFF_APPROACH] " + description)


func frames(count: int) -> void:
	for index: int in range(count): await physics_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var source_hash: String = FileAccess.get_sha256("res://monster_booster.ldtk")
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(480, 270)
	arena = WORLD.instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	await frames(90)
	var gameplay: Dictionary = {}
	for layer: Dictionary in arena.get("_level_layers") as Array:
		if str(layer.get("__identifier", "")) == "Gameplay": gameplay = layer
	var fixed_columns: int = int(gameplay.get("cliff_collision_fixed_columns", 0))
	check(fixed_columns == 116, "All 116 authored south-cliff columns lose the oversized solid skirt")
	var csv: Array = gameplay.intGridCsv as Array
	var width: int = int(gameplay.__cWid)
	check(int(csv[67 * width + 153]) == 6 and int(csv[68 * width + 153]) == 0 and int(csv[69 * width + 153]) == 0 and int(csv[70 * width + 153]) == 0,
		"The screenshot's cliff has a 16px foot blocker and 48px of newly free approach ground")
	var fronts: Array[Vector2] = [Vector2(240, 368), Vector2(512, 1312), Vector2(1488, 2224), Vector2(2368, 2560)]
	var stops: Array[Dictionary] = []
	var screenshot_x: float = 2448.0
	for front: Vector2 in fronts:
		var found: bool = false
		var middle: float = floorf((front.x + front.y) / 32.0) * 16.0 + 8.0
		for offset: float in [0.0, 16.0, -16.0, 32.0, -32.0, 48.0, -48.0]:
			var x: float = middle + offset
			if x < front.x + 8 or x > front.y - 8: continue
			player.position = Vector2(x, 1184)
			player.reset_physics_interpolation()
			var hit: KinematicCollision2D = player.move_and_collide(Vector2(0, -192))
			if hit == null or not str(hit.get_collider().name) == "MapLimits": continue
			if player.position.y < 1088.0 or player.position.y > 1093.0: continue
			found = true
			stops.append({"x": x, "player_y": player.position.y, "visible_foot_y": 1088.0})
			if front.x == 2368.0: screenshot_x = x
			break
		check(found, "Actual player reaches the visible foot without crossing cliff front " + str(front))
	var ramps: Array = arena.get_node("TerrainElevation").get("ramps") as Array
	check(ramps.size() == 3, "All three castle access ramps remain")
	for ramp: Dictionary in ramps:
		var rect: Rect2 = ramp.rect as Rect2
		var start: Vector2 = Vector2(rect.get_center().x, rect.end.y + 24.0)
		var finish: Vector2 = Vector2(rect.get_center().x, rect.position.y - 24.0)
		check(not player.test_move(Transform2D(0, start), finish - start), "Full passage remains open through ramp " + str(rect))
	player.position = Vector2(screenshot_x, 1184)
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.snap_floor_height()
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.35
	camera.force_update_scroll()
	player.set_physics_process(true)
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_W
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await frames(120)
	key.pressed = false
	Input.parse_input_event(key)
	await frames(1)
	check(player.position.y >= 1088.0 and player.position.y <= 1093.0, "Holding real movement input brings Nox to the cliff instead of an invisible rectangle below it")
	check(is_zero_approx(player.floor_height), "Approach remains on the lower ground plane")
	if rendered:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OUT + "cliff_contact.png") == OK, "The player/cliff contact screenshot saves")
	check(FileAccess.get_sha256("res://monster_booster.ldtk") == source_hash, "LDtk painting and authored ramp geometry remain unchanged")
	report = {"checks": checks, "fixed_columns": fixed_columns, "old_skirt_depth": 48, "new_blocker_depth": 16, "stops": stops, "input_stop": player.position, "failures": failures}
	var output: FileAccess = FileAccess.open(OUT + "regression.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("CLIFF_APPROACH_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", checks, " checks")
	quit(0 if failures.is_empty() else 1)
