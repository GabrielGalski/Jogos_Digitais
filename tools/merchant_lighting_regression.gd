extends SceneTree
## Real safe-room composition, emissive pixels, and light isolation.
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func capture(label: String) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	frame.save_png("res://renders/" + label + ".png")
	return frame

func _run() -> void:
	root.size = Vector2i(1024, 334)
	root.content_scale_size = Vector2i(1024, 334)
	change_scene_to_file("res://scenes/merchant_corridor.tscn")
	await process_frame
	await process_frame
	await create_timer(2.5).timeout
	var hall: Node2D = current_scene as Node2D
	check(int(hall.get("state")) == 2, "Merchant entrance did not finish")
	var rig: Node2D = hall.get_node("MerchantLighting") as Node2D
	var ambient: CanvasModulate = rig.get_node("WorldAmbient") as CanvasModulate
	check(ambient.color == Color("ad98b8"), "Merchant ambient does not use the darker violet base")
	var lights: Array[PointLight2D] = []
	var energies: Array[float] = []
	for child: Node in rig.get_children():
		if child is PointLight2D:
			var light: PointLight2D = child as PointLight2D
			lights.append(light)
			energies.append(light.energy)
			check(not light.shadow_enabled and light.energy > 0.0, "Merchant light is disabled or uses costly shadows")
		check(not child is Polygon2D, "Merchant added an explicit beam")
	check(lights.size() == 10, "Expected two facade, two door, five water and one Tin light")
	var facade_source: Sprite2D = hall.get_node("World/Toldo/Visual") as Sprite2D
	check((rig.get_node("FacadeNeon") as PointLight2D).global_position == facade_source.to_global(facade_source.get_rect().get_center()), "Facade light is not anchored to the active neon")
	check((rig.get_node("DoorNeon") as PointLight2D).position == Vector2(562.5, 150.5), "Door light does not match its actual seam")
	var tin: AnimatedSprite2D = hall.get_node("World/Merchant/Visual") as AnimatedSprite2D
	check(tin.modulate == Color.WHITE and tin.light_mask == 3, "Tin lost her authored colors or selective key light")
	check((rig.get_node("TinKey") as PointLight2D).range_item_cull_mask == 2, "Tin key light spills over the whole room")
	var neon_sprite: Sprite2D = rig.get_node("FacadeEmission") as Sprite2D
	check(neon_sprite.texture == facade_source.texture and neon_sprite.global_position == facade_source.to_global(facade_source.get_rect().position), "Neon emission is displaced from its authored pixels")
	var surface: Sprite2D = hall.get_node("World/Water/Surface") as Sprite2D
	var water: ShaderMaterial = surface.material as ShaderMaterial
	check(is_equal_approx(float(water.get_shader_parameter("night_level")), 0.78), "Water night exposure was not applied")
	check(surface.global_position == Vector2(-32, 263) and surface.region_rect.size == Vector2(1024, 39), "Lighting changed the water footprint")
	var threshold: Polygon2D = hall.get_node("World/HallDetails/DoorLight/Threshold") as Polygon2D
	var spill: ShaderMaterial = (hall.get_node("World/HallDetails/DoorLight/Spill") as Polygon2D).material as ShaderMaterial
	check(is_equal_approx(float(spill.get_shader_parameter("strength")), 0.30), "Door floor spill is not restrained")
	check((hall.get_node("World/DungeonDoorButton") as Button).disabled == false, "Lighting blocked the dungeon door")
	# Full-map camera for the comparison only; production camera is not edited.
	hall.set_physics_process(false)
	hall.set("ground_position", Vector2(350, 28))
	hall.set("displayed_height", 0.0)
	hall.call(&"_update_height", 0.0)
	var camera: Camera2D = hall.get_node("RoomCamera") as Camera2D
	camera.position = Vector2(480, 135)
	camera.zoom = Vector2.ONE
	camera.force_update_scroll()
	ambient.color = Color.WHITE
	for light: PointLight2D in lights:
		light.energy = 0.0
	neon_sprite.hide()
	tin.modulate = Color(0.86, 0.78, 0.86, 1.0)
	threshold.color = Color("5d2d43")
	spill.set_shader_parameter("light_color", Color("5d2d43"))
	spill.set_shader_parameter("strength", 1.0)
	water.set_shader_parameter("night_level", 1.0)
	water.set_shader_parameter("neon_reflections", 0.0)
	var before: Image = await capture("mercante_iluminacao_antes")
	ambient.color = Color("ad98b8")
	for index: int in range(lights.size()):
		lights[index].energy = energies[index]
	neon_sprite.show()
	rig.call(&"_bind_presentation")
	var after: Image = await capture("mercante_iluminacao_atual")
	if before != null and after != null:
		check(after.get_pixel(900, 70).get_luminance() < before.get_pixel(900, 70).get_luminance() * 0.85, "Unlit wall did not become darker")
		check(after.get_pixel(327, 57).get_luminance() >= before.get_pixel(327, 57).get_luminance() * 0.95, "Neon text lost its emitted brightness")
		check(after.get_pixel(271, 40).get_luminance() > after.get_pixel(900, 70).get_luminance() * 3.0, "Neon frame does not stand out from the wall")
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	hall.call(&"_fit_hall_camera")
	camera.position = Vector2(331, 135)
	camera.force_update_scroll()
	await capture("mercante_tin_iluminacao_atual")
	print("MERCHANT LIGHTING: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
