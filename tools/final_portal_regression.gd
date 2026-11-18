extends SceneTree
## Real six-altar events, symmetric castle layout and rendered alpha/color checks.

const WORLD: PackedScene = preload("res://scenes/maps/open_world.tscn")
const INSECTS: Script = preload("res://scripts/visual/insect_palettes.gd")
const BIOME: Script = preload("res://scripts/visual/biome_enemy_palette.gd")
const OUT: String = "res://output/final_portal/"
var failures: Array[String] = []
var checks: int = 0
var rendered: bool = false
var world: Node2D = null
var player: Player = null
var portal: Node2D = null
var review_camera: Camera2D = null


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func frame_at(point: Vector2) -> void:
	review_camera.global_position = point
	review_camera.reset_smoothing()
	review_camera.force_update_scroll()
	await ticks(3)


func place(feet: Vector2) -> void:
	player.global_position = feet - Vector2(0, 3)
	player.snap_floor_height()
	player.reset_physics_interpolation()


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "Capture " + label)


func native_layer(source: Sprite2D, label: String, elapsed: float = -1.0) -> Image:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(192, 112)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite: Sprite2D = source.duplicate() as Sprite2D
	sprite.position = Vector2.ZERO
	sprite.visible = true
	sprite.material = source.material.duplicate() as Material
	if elapsed >= 0.0:
		(sprite.material as ShaderMaterial).set_shader_parameter(&"elapsed", elapsed)
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Image = viewport.get_texture().get_image()
	check(result.save_png(OUT + label + ".png") == OK, "Native layer " + label)
	viewport.queue_free()
	await process_frame
	return result


func check_rendered_layers() -> void:
	var body: Sprite2D = portal.get_node("Presentation/Stone") as Sprite2D
	var runes: Sprite2D = portal.get_node("Presentation/Runes") as Sprite2D
	var static_sprite: Sprite2D = portal.get_node("Presentation/WhiteStatic") as Sprite2D
	var source: Image = body.texture.get_image()
	var mask: Image = static_sprite.texture.get_image()
	var stone: Image = await native_layer(body, "native_stone")
	var idle: Image = await native_layer(runes, "native_runes_idle")
	var preserved: bool = true
	var idle_correct: bool = true
	var recolored: int = 0
	for y: int in range(112):
		for x: int in range(192):
			var original: Color = source.get_pixel(x, y)
			var actual: Color = stone.get_pixel(x, y)
			if original.a8 != actual.a8:
				preserved = false
			if original == Color("#2e222f") or original == Color("#3e3546"):
				if original != actual:
					preserved = false
			elif original.a8 > 0 and original != actual:
				recolored += 1
			var rune: Color = idle.get_pixel(x, y)
			if mask.get_pixel(x, y).r8 > 0:
				if rune != Color("#3e3546"):
					idle_correct = false
			elif rune.a8 != 0:
				idle_correct = false
	check(preserved and recolored > 6000, "Stone recolors the base while preserving both arch colors and source alpha")
	check(idle_correct, "Only the 24 rune cutouts receive the exact idle color")
	var noise_a: Image = await native_layer(static_sprite, "native_static_a", 0.0)
	var noise_b: Image = await native_layer(static_sprite, "native_static_b", 0.75)
	var white_only: bool = true
	var clipped: bool = true
	var white_pixels: int = 0
	for y: int in range(112):
		for x: int in range(192):
			var pixel: Color = noise_a.get_pixel(x, y)
			if pixel.a8 == 0:
				continue
			white_pixels += 1
			if pixel != Color.WHITE:
				white_only = false
			if mask.get_pixel(x, y).g8 == 0:
				clipped = false
	check(white_only and clipped and white_pixels > 40 and white_pixels < 800, "Static contains only white pixels and transparency within the opening")
	check(noise_a.get_data() != noise_b.get_data(), "White noise visibly changes over time")


func check_palette_contract() -> void:
	for kind: StringName in [&"tall", &"fly", &"little"]:
		var colors: Array = INSECTS.PROPOSALS[0][kind] as Array
		check(colors[0] == "#D2AEC8" and colors[1] == "#70526F" and colors[3] == "#F0E3EB", "Shared light mauve palette for " + str(kind))
	var slime: PackedColorArray = BIOME.targets(&"slime")
	check(slime[0] == Color("#315767") and slime[1] == Color("#90DDD0"), "Slime has the requested mint body and dark blue shade")
	var skull: PackedColorArray = BIOME.targets(&"flying_skull")
	check(skull == PackedColorArray([Color("#F1934C"), Color("#FEFFE5"), Color("#81173F")]), "Skull original orange and cream are preserved")


func capture_enemy_palette() -> void:
	var gallery: Node2D = Node2D.new()
	gallery.position = Vector2(1728, 2600)
	gallery.z_index = 2
	world.add_child(gallery)
	var kinds: Array[String] = ["tall", "fly", "little", "flying_skull", "slime"]
	for index: int in range(kinds.size()):
		var kind: String = kinds[index]
		var slot: Node2D = Node2D.new()
		slot.position.x = float(index - 2) * 64.0
		gallery.add_child(slot)
		var visual: CanvasItem = null
		if index < 3:
			visual = (load("res://scripts/visual/insect_visual.gd") as Script).new() as AnimatedSprite2D
			visual.set("kind", StringName(kind))
			var profile: Resource = load("res://resources/enemies/insects/%s.tres" % kind) as Resource
			(visual as Node2D).scale = Vector2.ONE * float(profile.get("visual_scale"))
		else:
			visual = (load("res://scripts/visual/%s_visual.gd" % kind) as Script).new() as CanvasItem
		slot.add_child(visual)
		var label: Label = Label.new()
		label.position = Vector2(-28, -42)
		label.size = Vector2(56, 12)
		label.text = kind.capitalize().replace("Flying ", "")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", preload("res://assets/font/determination.ttf"))
		label.add_theme_font_size_override("font_size", 8)
		slot.add_child(label)
	place(gallery.global_position + Vector2(0, 60))
	await frame_at(gallery.global_position)
	await capture("enemy_palette")
	gallery.queue_free()
	await ticks(2)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
		root.content_scale_size = Vector2i(480, 270)
	world = WORLD.instantiate() as Node2D
	world.set("warp_entry_cutscene_enabled", false)
	root.add_child(world)
	current_scene = world
	var deadline: int = Time.get_ticks_msec() + 8000
	while not bool(world.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(world.get("entry_complete")), "Production world finishes loading")
	player = world.get_node("Nox") as Player
	player.contact_invulnerability = 1000.0
	player.set_physics_process(false)
	portal = world.get_node("FinalPortal") as Node2D
	check(portal.position.is_equal_approx(Vector2(1384, 288)), "Portal is centered at the top of the authored castle")
	check(is_equal_approx(float(portal.get("ground_height")), 56.0), "Portal art follows castle elevation")
	check(bool(world.call("is_ground_surface_point", portal.global_position)), "Final portal stands on actual ground")
	check((portal.get_node("Presentation/Stone") as Sprite2D).texture.resource_path.ends_with("final portal/portal1.png"), "Portal uses only portal1")
	check(not bool(portal.get("ready_for_final_battle")) and int(portal.get("active_runes")) == 0, "Portal starts locked with no charged runes")
	check_palette_contract()
	check(not world.has_node("CastleStairs"), "Stair artwork is removed")
	var left_altar: Node2D = null
	var right_altar: Node2D = null
	for altar: Node2D in world.get_node("HordePedestals").get("pedestals") as Array:
		var description: Dictionary = altar.get("data") as Dictionary
		if str(description.get("EncounterId", "")) == "room_2_castle_west":
			left_altar = altar
		if str(description.get("EncounterId", "")) == "room_2_castle_east":
			right_altar = altar
	check(left_altar != null and right_altar != null, "Both upper castle altars remain")
	if left_altar != null and right_altar != null:
		check(left_altar.position.is_equal_approx(Vector2(432, 448)), "Upper left altar keeps its authored location")
		check(right_altar.position.is_equal_approx(Vector2(2336, 448)), "Upper right altar moves right into the matching position")
		check(is_equal_approx((left_altar.position.x + right_altar.position.x) * 0.5, portal.position.x), "Final portal is centered between the two upper altars")
		check((right_altar.get("encounter") as Node2D).get("arena_center") == right_altar.position, "Moved altar retains its centered horde arena")
	if rendered:
		(player.get_node("Camera2D") as Camera2D).enabled = false
		review_camera = Camera2D.new()
		review_camera.zoom = Vector2.ONE * 0.18
		review_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		world.add_child(review_camera)
		review_camera.make_current()
		place(portal.global_position + Vector2(0, 72))
		await frame_at(Vector2(1384, 500))
		await capture("castle_layout")
		review_camera.zoom = Vector2.ONE * 0.96
		place(portal.global_position + Vector2(0, 72))
		await frame_at(portal.global_position - Vector2(0, 104))
		await capture("portal_0_altars")
		await check_rendered_layers()
	var encounters: Array = world.get_node("SpiritHordes").get("encounters") as Array
	check(encounters.size() == 6, "All six production altar encounters are tracked")
	for index: int in range(encounters.size()):
		var encounter: Node2D = encounters[index] as Node2D
		encounter.call("skip_to_completion")
		await ticks(2)
		var completed: int = index + 1
		check(int(portal.get("completed_altars")) == completed and int(portal.get("active_runes")) == completed * 4, "Each real cleared event lights four new runes")
		check(bool(portal.get("ready_for_final_battle")) == (completed == 6), "Readiness requires the sixth altar")
		check((portal.get_node("Presentation/WhiteStatic") as Sprite2D).visible == (completed == 6), "Static only activates with all six altars")
		encounter.emit_signal("cleared")
		check(int(portal.get("completed_altars")) == completed, "Duplicate completion cannot charge another group")
		if rendered and completed in [1, 3, 5, 6]:
			await capture("portal_%d_altars" % completed)
	check(bool(world.get_node("Gameplay").call("is_condition_met", "all_six_altars_clear")), "Six altars set the local readiness condition")
	check(not portal.has_signal("travel_requested") and not portal.has_method("can_travel"), "Final battle travel is not implemented")
	if rendered:
		await capture_enemy_palette()
	world.queue_free()
	await ticks(3)
	print("FINAL_PORTAL_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " | checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
