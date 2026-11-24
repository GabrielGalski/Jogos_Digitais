extends SceneTree
## Rendered review in the real purple world, followed by a 1x/3x recipe contact sheet.

const VISUAL: Script = preload("res://scripts/visual/weapons/procedural_projectile_visual.gd")
const SPIRIT: Script = preload("res://scripts/enemies/spirit_ghost.gd")
var arena: Node2D = null
var player: Player = null
var gun: Node2D = null
var controller: Node = null


func _initialize() -> void:
	_run.call_deferred()


func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/procedural_weapons/" + name + ".png")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/procedural_weapons")
	root.size = Vector2i(1280, 720)
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	await create_timer(1.0).timeout
	player = arena.get_node("Nox") as Player
	gun = player.get_node("BoosterShooter") as Node2D
	controller = player.get_node("GameplayKit/Manifestations")
	player.set_physics_process(false)
	gun.set_process(false)
	player.get_node("GameplayKit").set_process(false)
	player.get_node("GameplayKit/GameplayCameraRig").set_process(false)
	(arena.get_node("ArenaUI") as CanvasLayer).hide()
	player.position = Vector2(1120, 1560)
	player.snap_floor_height()
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	await process_frame
	var aim: Vector2 = Vector2(180, -100).normalized()
	var spirit: CharacterBody2D = SPIRIT.new() as CharacterBody2D
	arena.add_child(spirit)
	spirit.set_physics_process(false)
	spirit.set("resistance", 1000.0)
	spirit.set("max_resistance", 1000.0)
	spirit.global_position = player.surface_world_position() + aim * 165.0
	var models: Array[ProceduralManifestationModel] = controller.call("available_models")
	for index: int in range(models.size()):
		controller.call("cancel_attacks")
		controller.call("select_model", index)
		gun.set("aim_screen_override", root.get_canvas_transform() * (player.surface_world_position() + aim * 240.0))
		gun.set("shot_recoil", 0.0)
		gun.call("_update_rig", 0.0)
		var model: ProceduralManifestationModel = controller.call("selected_model") as ProceduralManifestationModel
		if model.family == ProceduralManifestationModel.Family.PROJECTILE:
			gun.call("fire_once")
		else:
			controller.call("set_trigger", true)
		await create_timer(0.13 if model.family == ProceduralManifestationModel.Family.PROJECTILE else 0.35).timeout
		await capture(String(model.code()))
		controller.call("set_trigger", false)
	controller.call("cancel_attacks")
	spirit.queue_free()
	await _gallery()
	print("PROCEDURAL_WEAPONS_CAPTURE PASS")
	quit(0)


func label(text: String, point: Vector2, tint: Color, size: int = 11) -> void:
	var item: Label = Label.new()
	item.text = text
	item.position = point
	item.z_index = 5
	item.add_theme_font_override("font", load("res://assets/font/determination.ttf") as Font)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", tint)
	item.add_theme_color_override("font_shadow_color", Color("#25131a"))
	item.add_theme_constant_override("shadow_offset_x", 1)
	item.add_theme_constant_override("shadow_offset_y", 1)
	arena.add_child(item)


func _gallery() -> void:
	root.content_scale_size = Vector2i(640, 360)
	(arena.get_node("PlayerHUD") as CanvasLayer).hide()
	player.hide()
	var camera: Camera2D = Camera2D.new()
	camera.position = Vector2(1136, 1560)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arena.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var factory: ProceduralWeaponSpriteFactory = controller.get("sprites") as ProceduralWeaponSpriteFactory
	label("PROJETEIS  |  COMPACTOS + LUMINOSOS", Vector2(845, 1400), Color("#f6ede5"), 13)
	var models: Array[ProceduralManifestationModel] = controller.call("available_models")
	var sprite_models: Array[ProceduralManifestationModel] = models.filter(
		func(model: ProceduralManifestationModel) -> bool: return model.family != ProceduralManifestationModel.Family.STREAM)
	var first_row: float = 1480.0 if sprite_models.size() > 6 else 1510.0
	var row_spacing: float = 101.0 if sprite_models.size() > 6 else 132.0
	for index: int in range(sprite_models.size()):
		var model: ProceduralManifestationModel = sprite_models[index]
		var point: Vector2 = Vector2(922 + (index % 3) * 212, first_row + floori(float(index) / 3.0) * row_spacing)
		label(String(model.code()) + "  " + model.card.display_name, point + Vector2(-76, -48), model.body_color)
		for zoom: int in [1, 3]:
			var sprite: Node2D = VISUAL.new() as Node2D
			arena.add_child(sprite)
			sprite.global_position = point + Vector2(-44 if zoom == 1 else 25, 0)
			sprite.scale = Vector2.ONE * float(zoom)
			sprite.call("configure", model, factory, Vector2.RIGHT)
			sprite.set("attached", true)
			label(str(zoom) + "x", sprite.global_position + Vector2(-6, 31), Color("#f6ede5"), 9)
		factory.rasterize(model, 0, 0).save_png("res://output/procedural_weapons/" + String(model.code()) + "_32.png")
	await create_timer(0.2).timeout
	await capture("gallery")
