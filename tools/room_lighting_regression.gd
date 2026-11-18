extends SceneTree
## Runtime wiring and rendered exposure/camera/UI checks on the actual Room_1 entry point.

const LIGHTING: Script = preload("res://scripts/visual/room_lighting.gd")
const PROFILE: Script = preload("res://scripts/visual/room_lighting_profile.gd")
var _failures: Array[String] = []
var _rendered: bool = false


func _initialize() -> void:
	_rendered = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	if _rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
	var packed: PackedScene = load("res://scenes/dungeon/ldtk_arena.tscn") as PackedScene
	var arena: Node2D = packed.instantiate() as Node2D
	# This suite isolates the active lighting profile; cycling is tested by room_lighting_setups_regression.
	arena.set("lighting_setups", null)
	arena.set("lighting_profile", (arena.get("lighting_profile") as Resource).duplicate(true))
	root.add_child(arena)
	current_scene = arena
	await process_frame
	await physics_frame
	var lighting: CanvasLayer = arena.get_node("RoomLighting") as CanvasLayer
	var actor: Node2D = arena.get_node("Nox") as Node2D
	var profile: Resource = lighting.get("profile") as Resource
	await process_frame
	_check(lighting.layer == 10, "World exposure must remain below HUD and parry overlays")
	_check(lighting.get("subject") == actor, "Light must track the real player")
	_check(actor.has_node("RoomContactShadow"), "Player must have the local elliptical contact shadow")
	_check(not (actor.get_node("GroundShadow") as CanvasItem).visible, "Only one player ground shadow should draw")
	_check(str(arena.get("level_name")) == "Room_1", "Main scene must remain Room_1")
	_check(not bool(arena.get("automatic_water")), "Room_1 must disable automatic background water")
	_check(not arena.has_node("Water"), "Room_1 without WaterArea must not instantiate a water surface")
	_check((arena.get_node("Backdrop") as Polygon2D).color.is_equal_approx(Color("#25131a")), "Room_1 must retain the standard background color")
	_check((arena.get_node("Borders") as Node2D).modulate.r > 1.5, "Room_1 borders must receive the requested brightness boost")
	_check(float(profile.get("radius")) <= 48.0, "Player light must use a much smaller radius")
	_check(float(profile.get("pixel_size")) == 2.0 and int(profile.get("brightness_steps")) == 0, "Room_1 light must use the softer 2 px grid without brightness bands")
	var material: ShaderMaterial = (lighting.get_node("WorldExposure") as ColorRect).material as ShaderMaterial
	lighting.call("update_frame")
	var expected_center: Vector2 = actor.global_transform * ((profile.get("center_offset") as Vector2)+actor.floor_visual_offset())
	_check((material.get_shader_parameter("center_world") as Vector2).is_equal_approx(expected_center), "Player light center must use the rendered world transform")
	if _rendered:
		while not bool(arena.get("entry_complete")):
			await process_frame
		await _capture("room1_dark_1280.png")
		var idle_radius: float = float(material.get_shader_parameter("radius"))
		profile.set("enabled", false)
		lighting.call("apply_profile")
		await process_frame
		_check((actor.get_node("GroundShadow") as CanvasItem).visible, "Disabling room exposure must restore the original player shadow")
		await _capture("room1_original_1280.png")
		profile.set("enabled", true)
		lighting.call("apply_profile")
		# Exercise the real gameplay path: continuous movement and the player's dash.
		var before_motion: Vector2 = actor.global_position
		var right_key: InputEventKey = InputEventKey.new()
		right_key.physical_keycode = KEY_D
		right_key.keycode = KEY_D
		right_key.pressed = true
		Input.parse_input_event(right_key)
		for step: int in range(20):
			await physics_frame
		await process_frame
		var walking_radius: float = float(material.get_shader_parameter("radius"))
		_check(walking_radius > idle_radius + 6.0, "Real walking must gradually expand the light")
		await _capture("room1_walking_1280.png")
		Input.action_press("dash")
		await physics_frame
		Input.action_release("dash")
		for step: int in range(20):
			await physics_frame
		right_key.pressed = false
		Input.parse_input_event(right_key)
		for step: int in range(3):
			await physics_frame
		lighting.call("update_frame")
		_check(actor.global_position.distance_to(before_motion) > 8.0, "The input scenario must actually move the player")
		var rendered_center: Vector2 = material.get_shader_parameter("center_world")
		_check(rendered_center.distance_to(actor.surface_world_position() + (profile.get("center_offset") as Vector2)) < 10.0, "Light must follow real player movement/dash without drifting")
		await _capture("room1_after_dash_1280.png")
		var shooter: Node2D = actor.get_node("BoosterShooter") as Node2D
		var projectile: Node2D = shooter.call("fire_once") as Node2D
		_check(projectile != null, "The lit scene must retain the real shooter/projectile gameplay path")
		for step: int in range(4):
			await physics_frame
		await _capture("room1_projectile_1280.png")
		await create_timer(3.0).timeout
		var resting_radius: float = float(material.get_shader_parameter("radius"))
		_check(resting_radius < walking_radius - 5.0, "Light must contract after the real player stops")
		await _capture("room1_resting_1280.png")
		print(JSON.stringify({"idle_radius":idle_radius,"walking_radius":walking_radius,"resting_radius":resting_radius}))
	arena.queue_free()
	await process_frame
	await _test_breathing()
	if _rendered:
		await _render_fixture()
	print(JSON.stringify({"ok": _failures.is_empty(), "rendered": _rendered, "failures": _failures}))
	quit(0 if _failures.is_empty() else 1)


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/room_lighting"))
	_check(root.get_texture().get_image().save_png("res://output/room_lighting/" + filename) == OK, "Capture failed: " + filename)


func _test_breathing() -> void:
	var world: Node2D = Node2D.new()
	root.add_child(world)
	var target: Node2D = Node2D.new()
	target.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(target)
	var exposure: CanvasLayer = LIGHTING.new() as CanvasLayer
	var test_profile: Resource = PROFILE.new()
	test_profile.set("contact_shadow_enabled", false)
	test_profile.set("breathing_amplitude", 0.0)
	exposure.set("profile", test_profile)
	exposure.set("subject", target)
	world.add_child(exposure)
	exposure.set_process(false)
	exposure.set_physics_process(false)
	var material: ShaderMaterial = (exposure.get_node("WorldExposure") as ColorRect).material as ShaderMaterial
	var rest_radius: float = float(material.get_shader_parameter("radius"))
	var moving_radii: Array[float] = []
	for fps: int in [30,120]:
		target.position = Vector2.ZERO
		exposure.call("bind_subject", target)
		var delta: float = 1.0 / fps
		for step: int in range(fps):
			target.position.x += float(test_profile.get("movement_reference_speed")) * delta
			exposure.call("_physics_process", delta)
			exposure.call("_process", delta)
		moving_radii.append(float(material.get_shader_parameter("radius")))
	_check(absf(moving_radii[0]-moving_radii[1]) < 0.02, "Expansion must be consistent at 30/120 FPS")
	_check(moving_radii[1] > rest_radius + 10.0 and moving_radii[1] < 40.0, "Walking radius must grow within the small-light envelope")
	for step: int in range(240):
		exposure.call("_physics_process", 1.0/60.0)
		exposure.call("_process", 1.0/60.0)
	var settled: float = float(material.get_shader_parameter("radius"))
	_check(absf(settled-rest_radius) < 1.0, "Standing still, including holding against a wall, must settle near idle radius")
	target.position += Vector2(300,0)
	exposure.call("_physics_process", 1.0/60.0)
	exposure.call("_process", 1.0/60.0)
	_check(float(material.get_shader_parameter("radius")) < rest_radius + 1.0, "Teleport must not count as walking")
	test_profile.set("breathing_amplitude", 0.035)
	exposure.call("bind_subject", target)
	var minimum: float = INF
	var maximum: float = 0.0
	for step: int in range(240):
		exposure.call("_physics_process", 1.0/60.0)
		exposure.call("_process", 1.0/60.0)
		var radius: float = float(material.get_shader_parameter("radius"))
		minimum = minf(minimum,radius)
		maximum = maxf(maximum,radius)
	_check(maximum-minimum > 1.5 and minimum > rest_radius*0.96 and maximum < rest_radius*1.04,
		"Idle breathing must remain a slow, bounded pulse")
	exposure.set_process(true)
	exposure.set_physics_process(true)
	paused = true
	var paused_radius: float = float(material.get_shader_parameter("radius"))
	for frame: int in range(4):
		await process_frame
	_check(is_equal_approx(float(material.get_shader_parameter("radius")),paused_radius), "Breathing must freeze while gameplay is paused")
	paused = false
	print(JSON.stringify({"breathing_min":minimum,"breathing_max":maximum,"walking_radius_30_120_fps":moving_radii,"settled_radius":settled}))
	world.queue_free()
	await process_frame


func _render_fixture() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(480, 270)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	root.add_child(viewport)
	var world: Node2D = Node2D.new()
	viewport.add_child(world)
	var floor_rect: Polygon2D = Polygon2D.new()
	floor_rect.z_index = -20
	floor_rect.polygon = PackedVector2Array([Vector2(-5000,-5000), Vector2(5000,-5000), Vector2(5000,5000), Vector2(-5000,5000)])
	var unshaded: Shader = Shader.new()
	unshaded.code = "shader_type canvas_item; render_mode unshaded; void fragment(){COLOR=vec4(0.6,0.5,0.4,1.0);}"
	var surface_material: ShaderMaterial = ShaderMaterial.new()
	surface_material.shader = unshaded
	floor_rect.material = surface_material
	world.add_child(floor_rect)
	var target: Node2D = Node2D.new()
	target.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	target.position = Vector2(240,135)
	world.add_child(target)
	var exposure: CanvasLayer = LIGHTING.new() as CanvasLayer
	var fixture_profile: Resource = PROFILE.new()
	fixture_profile.set("radius", 90.0)
	fixture_profile.set("breathing_enabled", false)
	fixture_profile.set("clear_center_ratio", 0.25)
	fixture_profile.set("center_multiplier", Color.WHITE)
	fixture_profile.set("pixel_size", 0.0)
	fixture_profile.set("brightness_steps", 0)
	fixture_profile.set("center_offset", Vector2.ZERO)
	fixture_profile.set("contact_shadow_enabled", false)
	exposure.set("profile", fixture_profile)
	exposure.set("subject", target)
	viewport.add_child(exposure)
	var hud: CanvasLayer = CanvasLayer.new()
	hud.layer = 90
	viewport.add_child(hud)
	var hud_rect: ColorRect = ColorRect.new()
	hud_rect.size = Vector2(16,16)
	hud.add_child(hud_rect)
	for transform_index: int in range(3):
		if transform_index == 1:
			target.position += Vector2(38,-19)
			viewport.canvas_transform = Transform2D(0.4, Vector2(1.7,1.7), 0.0, Vector2(-80,-140))
		elif transform_index == 2:
			viewport.canvas_transform = Transform2D(-0.25, Vector2(0.7,0.7), 0.0, Vector2(70,90))
			fixture_profile.set("pixel_size", 4.0)
			fixture_profile.set("brightness_steps", 6)
			exposure.call("apply_profile")
		await process_frame
		exposure.call("update_frame")
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		_check(image.get_pixel(4,4).r > 0.98, "HUD must remain bright above world exposure")
		var inverse: Transform2D = viewport.canvas_transform.affine_inverse()
		var differences: int = 0
		for y: int in range(24,260,12):
			for x: int in range(24,470,12):
				var world_point: Vector2 = inverse * Vector2(x+0.5,y+0.5)
				if transform_index == 2:
					world_point = ((world_point / 4.0).floor() + Vector2.ONE * 0.5) * 4.0
				var distance_to_player: float = world_point.distance_to(target.position)
				var falloff: float = smoothstep(22.5,90.0,distance_to_player)
				if transform_index == 2:
					falloff = floorf(falloff * 6.0 + 0.5) / 6.0
				var ambient: Color = fixture_profile.get("ambient_multiplier")
				var exposure_color: Color = Color.WHITE.lerp(ambient,falloff)
				var expected: Color = Color(0.6*exposure_color.r,0.5*exposure_color.g,0.4*exposure_color.b)
				var actual: Color = image.get_pixel(x,y)
				if absf(actual.r-expected.r)>0.025 or absf(actual.g-expected.g)>0.025 or absf(actual.b-expected.b)>0.025:
					differences += 1
		_check(differences == 0, "Rendered gradient must follow world distance under movement/zoom/rotation; samples off: " + str(differences))
	exposure.call("bind_subject", null)
	await process_frame
	await RenderingServer.frame_post_draw
	var no_subject: Image = viewport.get_texture().get_image()
	var ambient_gain: Color = fixture_profile.get("ambient_multiplier")
	_check(absf(no_subject.get_pixel(240,135).r-0.6*ambient_gain.r)<0.025, "A missing player must fall back to ambient exposure")
	# Confirm the brightness really reaches the rendered TileMap children, not just the parent.
	fixture_profile.set("enabled", false)
	exposure.call("apply_profile")
	viewport.canvas_transform = Transform2D.IDENTITY
	var border_script: Script = load("res://scripts/dungeon/ldtk_borders.gd") as Script
	var texture_script: Script = load("res://scripts/dungeon/ldtk_texture_source.gd") as Script
	var border: Node2D = border_script.new() as Node2D
	border.set("brightness", 1.65)
	world.add_child(border)
	border.call("build", [{"__identifier":"Borders", "__tilesetDefUid":1,
		"gridTiles":[{"px":[32,32],"src":[0,96],"f":0}]}],
		{1:{"relPath":"assets/tiles/wall/bordas.png","tileGridSize":8}}, texture_script.new())
	await process_frame
	await RenderingServer.frame_post_draw
	var bright_border: Color = viewport.get_texture().get_image().get_pixel(34,34)
	_check(absf(bright_border.r-83.0/255.0*1.65)<0.02 and absf(bright_border.g-48.0/255.0*1.65)<0.02,
		"Rendered border pixels must be 1.65 times brighter than the source")
	viewport.queue_free()
	await process_frame
