extends SceneTree
## Deterministic current-map views for comparing tree shadows with clouds off/on.
## Run rendered with -- --label=antes (or depois).

var arena: Node2D = null
var camera: Camera2D = null
var label: String = "depois"


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
	_run.call_deferred()


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://output/sombras_arvores/" + label + "/" + file_name + ".png"
	var result: Error = root.get_texture().get_image().save_png(path)
	if result != OK:
		push_error("Unable to save shadow view: " + path)
		quit(1)


func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.content_scale_size = Vector2i(1200, 800)
	DirAccess.make_dir_recursive_absolute("res://output/sombras_arvores/" + label)
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	await create_timer(0.8).timeout
	(arena.get_node("RoomLighting") as CanvasLayer).hide()
	(arena.get_node("PlayerHUD") as CanvasLayer).hide()
	(arena.get_node("ArenaUI") as CanvasLayer).hide()
	var player: Node2D = arena.get_node("Nox") as Node2D
	player.hide()
	player.set_process(false)
	player.set_physics_process(false)
	var clouds: Node = arena.get_node("TerrainCloudShadows")
	clouds.set_physics_process(false)
	clouds.call("set_elapsed", 12.5)
	var materials: Dictionary = clouds.get("palette_materials") as Dictionary
	camera = Camera2D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 2.0
	arena.add_child(camera)
	camera.make_current()
	var views: Array[Dictionary] = [
		{"name": "01_sul", "point": Vector2(1760, 3060)},
		{"name": "02_leste", "point": Vector2(3510, 2750)},
		{"name": "03_sudeste", "point": Vector2(3440, 3050)},
		{"name": "04_oeste", "point": Vector2(190, 2760)},
	]
	for enabled: bool in [false, true]:
		for material: ShaderMaterial in materials.values():
			material.set_shader_parameter(&"clouds_enabled", enabled)
		for view: Dictionary in views:
			camera.position = view.point as Vector2
			camera.force_update_scroll()
			await _capture(str(view.name) + ("_nuvens" if enabled else "_sem_nuvens"))
	for material: ShaderMaterial in materials.values():
		material.set_shader_parameter(&"clouds_enabled", false)
	camera.position = Vector2(1848, 1624)
	camera.zoom = Vector2.ONE * 0.30
	camera.force_update_scroll()
	await _capture("05_mapa_sem_nuvens")
	print("TREE_SHADOWS_CAPTURE PASS " + label)
	quit(0)
