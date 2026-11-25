extends SceneTree
## Real upper-plateau seams: closed terrain joins, exposed river and GPU coverage.

const MAP: String = "res://monster_booster.ldtk"
const OUTPUT: String = "res://output/cliff_gaps/"
const JOINTS: Array[Vector2i] = [Vector2i(2623, 350), Vector2i(2607, 493),
	Vector2i(2575, 603), Vector2i(2559, 700), Vector2i(2543, 940)]
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _image() -> Image:
	await physics_frame
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _difference(first: Color, second: Color) -> float:
	return Vector3(first.r - second.r, first.g - second.g, first.b - second.b).length()


func _run() -> void:
	var original_map: String = FileAccess.get_sha256(MAP)
	var original_atlas: String = FileAccess.get_sha256("res://assets/tiles/floor/cliff_tileset.png")
	root.size = Vector2i(960, 720)
	root.content_scale_size = root.size
	var arena: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	var deadline: int = Time.get_ticks_msec() + 3000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(arena.get("entry_complete")), "Map entry fade has finished before comparing GPU pixels")
	await physics_frame
	await physics_frame
	var player: Player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	player.position = Vector2(2400, 550)
	player.snap_floor_height()
	player.get_node("GameplayKit").process_mode = Node.PROCESS_MODE_DISABLED
	player.get_node("BoosterShooter").set_process(false)
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	water.set_process(false)
	water.set_elapsed(12.0)
	var region: Node2D = water.regions[0]
	var surface: Sprite2D = region.get_node("Surface") as Sprite2D
	var mask: Image = surface.texture.get_image()
	var rect: Rect2 = region.get_meta(&"authored_rect") as Rect2
	check(mask.get_format() == Image.FORMAT_LA8, "Cliff sealing retains the compact native water mask")
	for point: Vector2i in JOINTS:
		var local: Vector2i = point - Vector2i(rect.position)
		check(mask.get_pixelv(local).a8 == 0, "No water through the internal cliff joint at " + str(point))
		check(mask.get_pixelv(local + Vector2i(32, 0)).a8 == 255, "The irregular exterior still exposes the river beside " + str(point))
	check(mask.get_pixelv(Vector2i(2552, 1087) - Vector2i(rect.position)).a8 == 0, "The last 16 px cliff tile joins the lower floor without a water slit")
	check(mask.get_pixelv(Vector2i(2592, 1086) - Vector2i(rect.position)).a8 == 255, "Actual water at the cliff foot remains visible")
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(OUTPUT)
		arena.get_node("TerrainCloudShadows").set_process(false)
		(arena.get_node("RoomLighting") as CanvasLayer).hide()
		(arena.get_node("PlayerHUD") as CanvasLayer).hide()
		(arena.get_node("ArenaUI") as CanvasLayer).hide()
		var camera: Camera2D = Camera2D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.zoom = Vector2.ONE * 3.0
		arena.add_child(camera)
		camera.make_current()
		for index: int in range(JOINTS.size()):
			camera.position = Vector2(JOINTS[index]) + Vector2.ONE * 0.5
			camera.force_update_scroll()
			water.show()
			var visible: Image = await _image()
			visible.save_png(OUTPUT + "joint_%d.png" % index)
			water.hide()
			var hidden: Image = await _image()
			var center: Vector2i = Vector2i(Vector2(root.size) * 0.5)
			check(_difference(visible.get_pixelv(center), hidden.get_pixelv(center)) < 0.005, "Rendered joint hides water completely: " + str(JOINTS[index]))
			var outside: Vector2i = center + Vector2i(96, 0)
			check(_difference(visible.get_pixelv(outside), hidden.get_pixelv(outside)) > 0.04, "Rendered river is preserved outside the cliff: " + str(JOINTS[index]))
		water.show()
	check(FileAccess.get_sha256(MAP) == original_map, "Current LDtk painting is unchanged")
	check(FileAccess.get_sha256("res://assets/tiles/floor/cliff_tileset.png") == original_atlas, "The source cliff atlas is unchanged")
	print("CLIFF_WATER_GAPS_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
