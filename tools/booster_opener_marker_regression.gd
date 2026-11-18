extends SceneTree
## Compare the two preview props through real proximity, E input and rendering.

const PREVIEW_PATH: String = "res://scenes/previews/booster_opener_preview.tscn"
const OUT: String = "res://output/booster_opener_comparison/"

var failures: Array[String] = []
var checks: int = 0
var scene: Node2D = null
var player: Player = null


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("BOOSTER_MARKER: " + message)


func ticks(count: int) -> void:
	for _tick: int in range(count):
		await physics_frame
	await process_frame


func place(feet: Vector2) -> void:
	player.position = feet - Vector2(0, 3)
	player.velocity = Vector2.ZERO
	player.snap_floor_height()
	player.reset_physics_interpolation()


func press_e() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = KEY_E
		event.keycode = KEY_E
		event.pressed = pressed
		Input.parse_input_event(event)
		await ticks(1)


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "Saved " + label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	# The preview references autoloads, so load after the SceneTree initializes them.
	var preview: PackedScene = load(PREVIEW_PATH) as PackedScene
	scene = preview.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Actors/Nox") as Player
	await ticks(30)
	var original: Node2D = scene.get_node("Actors/HordePlatform/BoosterOpener") as Node2D
	var marked: Node2D = scene.get_node("Actors/MarkedBoosterOpener") as Node2D
	var marker: Node2D = marked.get_node("Visuals/ExclamationMarker") as Node2D
	var symbol: AnimatedSprite2D = marker.get_node("Exclamation") as AnimatedSprite2D
	var yellow_light: PointLight2D = marker.get_node("YellowLight") as PointLight2D
	var original_surface: AnimatedSprite2D = original.get_node("Visuals/Surface") as AnimatedSprite2D
	var marked_surface: AnimatedSprite2D = marked.get_node("Visuals/Surface") as AnimatedSprite2D
	check(marked.global_position.x > original.global_position.x + 96.0, "Marked opener is to the right with clear separation")
	check(marked.get_parent() == scene.get_node("Actors") and not marked.has_node("Plate"), "Right opener stands directly on the floor")
	check(marked_surface.global_scale.is_equal_approx(original_surface.global_scale), "Both openers have the same gameplay scale")
	check(not bool(marked.get("interaction_enabled")), "Marked opener is configured as noninteractive")
	check(symbol.sprite_frames.get_frame_count(&"idle") == 8, "All eight authored exclamation frames are used")
	check(symbol.sprite_frames.get_animation_loop(&"idle") and symbol.is_playing(), "Exclamation animation loops continuously")
	check(symbol.sprite_frames.get_frame_texture(&"idle", 0).get_size() == Vector2(32, 32), "Enlarged source art uses native pixel resolution")
	var palette: ShaderMaterial = symbol.material as ShaderMaterial
	var yellow: Color = palette.get_shader_parameter("golden_yellow") as Color
	var orange: Color = palette.get_shader_parameter("shadow_orange") as Color
	check(yellow.r > 0.95 and yellow.g > 0.75 and yellow.b < 0.4, "Marker's main palette is yellow")
	check(orange.r > 0.7 and orange.g > 0.3 and orange.g < 0.6 and orange.b < 0.2, "Marker's shadows are orange")
	check(yellow_light.enabled and yellow_light.energy > 0.0 and yellow_light.color.r > yellow_light.color.b, "Marker emits warm yellow light")
	var lighting: CanvasLayer = scene.get_node("RoomLighting") as CanvasLayer
	check((lighting.get("profile") as Resource).resource_path == "res://resources/visual/room_1_lighting.tres", "Preview uses the game's existing light grade")
	check((scene.get_node("HUD") as CanvasLayer).layer > lighting.layer, "World light grade stays below the HUD")
	check((player.get_node("Camera2D") as Camera2D).zoom.is_equal_approx(Vector2(0.96, 0.96)), "Gameplay camera distance is preserved")
	await capture("01-both-closed")
	place(Vector2(136, 25))
	await ticks(10)
	var animation_frames: Dictionary[int, bool] = {}
	var floating_positions: Dictionary[int, bool] = {}
	for _sample: int in range(8):
		await ticks(6)
		animation_frames[symbol.frame] = true
		floating_positions[roundi(marker.global_position.y)] = true
		check(str(marked.get("state")) == "closed" and is_zero_approx(float(marked.get("open_amount"))), "Proximity never opens the marked prop")
	await press_e()
	check(int(marked.get("interaction_count")) == 0, "E cannot activate the marked prop")
	check(not (marked.get_node("ActionPrompt") as Sprite2D).visible, "Marked prop never shows an E prompt")
	check(not (marked.get_node("Visuals/Beam") as Node2D).visible and not (marked.get_node("Visuals/ApertureGlow") as Sprite2D).visible, "Marked prop has no opening effect")
	check(not (marked.get_node("Visuals/Cards/Center") as Sprite2D).visible, "Marked prop has no floating cards")
	check(animation_frames.size() > 2 and floating_positions.size() > 1, "Marker both animates its frames and floats vertically")
	await capture("02-marker-close-up-gameplay")
	place(Vector2(0, 30))
	var deadline: int = Time.get_ticks_msec() + 3000
	while str(original.get("state")) != "opened" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(str(original.get("state")) == "opened", "Original altar still opens on approach")
	await press_e()
	check(int(original.get("interaction_count")) == 1, "Original altar still responds to E")
	check((original.get_node("Visuals/OpeningLight") as PointLight2D).energy > 0.0, "Original altar illuminates its surroundings when open")
	check(str(marked.get("state")) == "closed" and int(marked.get("interaction_count")) == 0, "Original altar cannot change the marked prop")
	place(Vector2(60, 30))
	await ticks(45)
	await capture("03-comparison-gameplay")
	scene.queue_free()
	await ticks(3)
	var report: Dictionary = {"ok": failures.is_empty(), "checks": checks, "failures": failures}
	var report_file: FileAccess = FileAccess.open(OUT + "marker-regression.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	print("BOOSTER_MARKER_REGRESSION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
