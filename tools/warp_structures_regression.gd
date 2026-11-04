extends SceneTree
## Native runtime checks for centre-aligned arrivals, masks and the central plaza.

const OUT: String = "res://output/warp_structures/"
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)


func _image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _mask_counts(visual: Node2D) -> Vector2i:
	var sprite: Sprite2D = visual.get("inscriptions") as Sprite2D
	var mask: Image = sprite.texture.get_image()
	var result: Vector2i = Vector2i.ZERO
	for y: int in range(mask.get_height()):
		for x: int in range(mask.get_width()):
			var pixel: Color = mask.get_pixel(x, y)
			if pixel.r > 0.5: result.x += 1
			if pixel.g > 0.5: result.y += 1
	check(mask.get_pixel(0, 0).r < 0.01 and mask.get_pixel(0, 0).g < 0.01, "The transparent exterior remains empty")
	return result


func _wait_entry(arena: Node2D) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame


func _run() -> void:
	var hashes: Dictionary = {}
	for path: String in ["res://monster_booster.ldtk", "res://assets/tiles/structures/warp.png", "res://assets/tiles/structures/central_warp.png"]:
		hashes[path] = FileAccess.get_sha256(path)
	var arena: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	await _wait_entry(arena)
	var player: Player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.get_node("GameplayKit").process_mode = Node.PROCESS_MODE_DISABLED
	var gates: Array = arena.get_node("Warps").get("gates") as Array
	check(gates.size() == 1, "The central warp replaces the reserved central pedestal and old arrival")
	var central_gate: Node2D = gates[0] as Node2D
	check(bool((central_gate.get("data") as Dictionary).get("Central", false)), "CentralWarp is a first-class LDtk entity")
	check(player.position.is_equal_approx(central_gate.call("spawn_position") as Vector2), "Open-world arrival uses the raised warp spawn")
	check(player.to_global(Vector2(0, 3)) + player.floor_visual_offset() == central_gate.global_position, "Projected arrival feet stay in the diamond centre")
	check(bool(central_gate.call("supports_feet", central_gate.to_global(Vector2.ZERO))), "The transparent writing never creates a hole in warp interaction")
	check(not bool(central_gate.call("supports_feet", central_gate.to_global(Vector2(110, 0)))), "The exterior is outside the interaction footprint")
	check(not bool(central_gate.call("can_travel")), "The future final-boss destination is still unimplemented")
	var visual: Node2D = central_gate.get_node("Presentation") as Node2D
	var plate: Sprite2D = visual.get("plate") as Sprite2D
	check(plate.texture.get_size() == Vector2(192, 256), "The original central warp image retains its native resolution")
	check(plate.texture.get_size() * visual.scale == Vector2(192, 256), "The central warp retains its full authored size")
	var counts: Vector2i = _mask_counts(visual)
	check(counts.x == 0 and counts.y > 600, "Only the central inscriptions are coloured on the large warp")
	check(not visual.is_processing() and not visual.has_node("AmberGroundLight"), "Warp markings are static and have no gradient halo")
	var found_plaza: bool = false
	for node: Node in arena.get_node("LdtkLayers").get_children():
		if node is TileMapLayer and str(node.name).begins_with("Floor_WarpPlaza"):
			found_plaza = true
			check((node as TileMapLayer).get_used_cells().size() == 705, "All authored plaza tiles load")
			check(int(node.get_meta(&"asset_palette")) == 0, "The plaza shares the source path palette")
	check(found_plaza, "The scenery room provides the central plaza")
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(OUT)
		root.size = Vector2i(960, 720)
		root.content_scale_size = root.size
		for child: Node in arena.get_children():
			if child is CanvasLayer: (child as CanvasLayer).hide()
		# Keep the actual exposure profile in this preview.
		(arena.get_node("RoomLighting") as CanvasLayer).show()
		var camera: Camera2D = Camera2D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.position = Vector2(1864, 1768)
		camera.zoom = Vector2.ONE * 1.5
		arena.add_child(camera)
		camera.make_current()
		camera.force_update_scroll()
		var frame: Image = await _image()
		frame.save_png(OUT + "central_warp.png")
	arena.queue_free()
	await process_frame
	var room: Node2D = (load("res://scenes/dungeon/ldtk_arena.tscn") as PackedScene).instantiate() as Node2D
	room.set("warp_entry_cutscene_enabled", false)
	root.add_child(room)
	current_scene = room
	await _wait_entry(room)
	var regular_player: Player = room.get_node("Nox") as Player
	regular_player.set_physics_process(false)
	var regular_gate: Node2D = room.get("_arrival_gate") as Node2D
	check(regular_player.position.is_equal_approx(regular_gate.position - Vector2(0, 3)), "Regular LDtk arrival also puts feet in the centre")
	var regular_visual: Node2D = regular_gate.get_node("Presentation") as Node2D
	check(regular_visual.scale == Vector2.ONE * 0.5, "Only the common warp is reduced to half size")
	check((regular_visual.get("plate") as Sprite2D).texture.get_size() * regular_visual.scale == Vector2(48, 48), "The common warp displays at 48x48 without modifying its source")
	check(bool(regular_gate.call("supports_feet", regular_gate.to_global(Vector2(20, 0)))), "Interaction reaches the resized common warp")
	check(not bool(regular_gate.call("supports_feet", regular_gate.to_global(Vector2(30, 0)))), "Interaction does not extend past the resized common warp")
	counts = _mask_counts(regular_visual)
	check(counts.x > 150 and counts.y > 30, "Regular warp fills both the central square and lateral symbols")
	check(not regular_visual.is_processing(), "Regular warp has no animation clock")
	if "--capture" in OS.get_cmdline_user_args():
		for child: Node in room.get_children():
			if child is CanvasLayer: (child as CanvasLayer).hide()
		(room.get_node("RoomLighting") as CanvasLayer).show()
		var camera: Camera2D = Camera2D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.position = regular_gate.position
		camera.zoom = Vector2.ONE * 4.0
		room.add_child(camera)
		camera.make_current()
		camera.force_update_scroll()
		var first: Image = await _image()
		first.save_png(OUT + "regular_warp.png")
	room.queue_free()
	await process_frame
	var tutorial: Node2D = (load("res://scenes/tutorial_arena.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(tutorial)
	current_scene = tutorial
	var tutorial_player: Player = tutorial.get_node("Mox") as Player
	tutorial_player.set_physics_process(false)
	var entrance: Node2D = tutorial.get_node("EntranceWarp") as Node2D
	check(entrance.scale == Vector2.ONE * 0.5, "Asterion uses the same reduced common warp")
	check(tutorial_player.position.is_equal_approx(entrance.position - Vector2(0, 3)), "Asterion arrival uses the same centre convention")
	check(entrance.has_node("Inscriptions"), "Asterion uses the same recoloured warp presentation")
	# Let the finite entry tween finish before freeing its owner.
	var tutorial_deadline: int = Time.get_ticks_msec() + 3000
	while not bool(tutorial.get("entrance_complete")) and Time.get_ticks_msec() < tutorial_deadline:
		await process_frame
	for path: String in hashes:
		check(FileAccess.get_sha256(path) == str(hashes[path]), "Runtime preserves the authored map and source sprites: " + path)
	print("WARP_STRUCTURES_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	tutorial.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
