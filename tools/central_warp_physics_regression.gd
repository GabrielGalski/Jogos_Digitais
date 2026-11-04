extends SceneTree
## Real input, capsule collision, projected relief and pixel checks in the open map.

const OUT: String = "res://output/central_warp_physics/"
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, description: String) -> void:
	if not value:
		failures.append(description)
		push_error(description)


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _place(player: Player, feet: Vector2) -> void:
	player.position = feet - Vector2(0, 3)
	player.velocity = Vector2.ZERO
	player.snap_floor_height()


func _approach(player: Player, center: Vector2, offset: Vector2, forward: Key, backward: Key, count: int, elevation: float) -> void:
	_place(player, center + offset)
	check(is_zero_approx(player.floor_height), "Approach begins at ground height: " + str(offset))
	var body_rest: float = player.body.position.y
	var weapon_rest: float = (player.get_node("BoosterShooter") as Node2D).position.y
	var shadow_rest: float = (player.get_node("RoomContactShadow") as Node2D).position.y
	_key(forward, true)
	await _ticks(count)
	_key(forward, false)
	await _ticks(3)
	check(is_equal_approx(player.floor_height, elevation) and is_equal_approx(player.displayed_height, elevation), "Nox climbs to the configured height with actual input: " + str(offset))
	check(is_equal_approx(player.body.position.y, body_rest - elevation), "Nox sprite projects onto the top")
	check(is_equal_approx((player.get_node("BoosterShooter") as Node2D).position.y, weapon_rest - elevation), "Weapon follows the same height")
	check(is_equal_approx((player.get_node("RoomContactShadow") as Node2D).position.y, shadow_rest - elevation), "Contact shadow follows the same height")
	_key(backward, true)
	await _ticks(count)
	_key(backward, false)
	await _ticks(3)
	check(is_zero_approx(player.floor_height) and is_zero_approx(player.displayed_height), "Stepping down returns to the ground: " + str(offset))


func _frame() -> Image:
	await _ticks(2)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _pixel(image: Image, world_point: Vector2) -> Color:
	var scale: Vector2 = Vector2(image.get_size()) / root.get_visible_rect().size
	var pixel: Vector2i = Vector2i(((root.get_canvas_transform() * world_point) * scale).round())
	return image.get_pixelv(pixel.clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE))


func _run() -> void:
	var map_hash: String = FileAccess.get_sha256("res://monster_booster.ldtk")
	var arena: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	var deadline: int = Time.get_ticks_msec() + 4000
	while not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(bool(arena.get("entry_complete")), "Arrival completes")
	var player: Player = arena.get_node("Nox") as Player
	player.contact_invulnerability = 1000.0
	player.get_node("GameplayKit").process_mode = Node.PROCESS_MODE_DISABLED
	arena.get_node("FlyingEyeZones").process_mode = Node.PROCESS_MODE_DISABLED
	var gate: Node2D = arena.get("_arrival_gate") as Node2D
	var platform: Node2D = gate.get_node("Platform") as Node2D
	var elevation: float = float(platform.get("elevation"))
	var display_scale: float = float(platform.get("display_scale"))
	check(player.displayed_height == elevation, "Arrival starts on the elevated platform")
	check(player.to_global(Vector2(0, 3)) + player.floor_visual_offset() == gate.global_position, "Raised arrival still aligns with the authored diamond")
	check(is_equal_approx(float(arena.get_node("TerrainElevation").call("height_at", gate.global_position)), 0.0), "Platform relief does not raise the ground artwork")
	var stair_top: float = 78.0 * display_scale + elevation
	var stair_bottom: float = 146.0 * display_scale
	check(is_equal_approx(float(platform.call("height_at", gate.to_global(Vector2(0, (stair_top + stair_bottom) * 0.5)))), elevation * 0.5), "The middle of the southern stair has half height")
	check(is_equal_approx(float(platform.call("height_at", gate.to_global(Vector2(0, stair_top)))), elevation), "The stair joins the top without a low seam")
	check(is_equal_approx(float(platform.call("height_at", gate.to_global(Vector2(0, stair_top - 1)))), elevation), "The top stays high immediately before the stair")
	if "--skip-walk" not in OS.get_cmdline_user_args():
		await _approach(player, gate.global_position, Vector2(112, 8) * display_scale, KEY_A, KEY_D, roundi(56 * display_scale), elevation)
		await _approach(player, gate.global_position, Vector2(-112, 8) * display_scale, KEY_D, KEY_A, roundi(56 * display_scale), elevation)
		await _approach(player, gate.global_position, Vector2(0, -88) * display_scale, KEY_S, KEY_W, roundi(56 * display_scale), elevation)
		await _approach(player, gate.global_position, Vector2(0, 160) * display_scale, KEY_W, KEY_S, roundi(72 * display_scale), elevation)
	player.set_physics_process(false)
	var pillars: Array = platform.get("pillars") as Array
	check(pillars.size() == 4, "Exactly four authored pillars get physical bases")
	var enemy: CharacterBody2D = CharacterBody2D.new()
	enemy.collision_layer = 4
	enemy.collision_mask = 1
	var enemy_shape: CollisionShape2D = CollisionShape2D.new()
	var enemy_circle: CircleShape2D = CircleShape2D.new()
	enemy_circle.radius = 6
	enemy_shape.shape = enemy_circle
	enemy.add_child(enemy_shape)
	arena.add_child(enemy)
	await _ticks(2)
	for pillar: Node2D in pillars:
		var solid: StaticBody2D = pillar.get_node("SolidBase") as StaticBody2D
		var capsule: CapsuleShape2D = (solid.get_node("Footprint") as CollisionShape2D).shape as CapsuleShape2D
		check(is_equal_approx(capsule.height, 20 * display_scale) and is_equal_approx(capsule.radius, 5 * display_scale), "Physical bases follow the artwork scale")
		var foot: Vector2 = solid.global_position
		check(player.test_move(Transform2D(0, foot + Vector2(-32, -3)), Vector2(64, 0)), "Nox is blocked by " + str(pillar.name))
		check(enemy.test_move(Transform2D(0, foot + Vector2(-32, 0)), Vector2(64, 0)), "Enemy physics is blocked by " + str(pillar.name))
		check(not player.test_move(Transform2D(0, foot + Vector2(-32, -19)), Vector2(64, 0)), "There is a passage behind " + str(pillar.name))
		check(pillar.z_index == player.z_index and not pillar.z_as_relative, "Pillar participates in actor depth sorting")
		enemy.position = foot + Vector2(96, 96)
	enemy.queue_free()
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(OUT)
		root.size = Vector2i(960, 720)
		root.content_scale_size = root.size
		for child: Node in arena.get_children():
			if child is CanvasLayer: (child as CanvasLayer).hide()
		var cloud_clock: Node = arena.get_node("TerrainCloudShadows")
		cloud_clock.set_physics_process(false)
		var variants: Array = (cloud_clock.get("palette_materials") as Dictionary).values()
		variants.append_array(cloud_clock.get("_additional_materials") as Array)
		for variant: ShaderMaterial in variants:
			variant.set_shader_parameter(&"clouds_enabled", false)
		var camera: Camera2D = Camera2D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.position = gate.global_position + Vector2(0, 16)
		camera.zoom = Vector2.ONE * 1.5
		arena.add_child(camera)
		camera.make_current()
		camera.force_update_scroll()
		_place(player, gate.global_position + Vector2(0, elevation))
		var image: Image = await _frame()
		image.save_png(OUT + "plaza_and_platform.png")
		var plaza_pixel: Color = _pixel(image, gate.global_position + Vector2(-120, 0))
		var path_pixel: Color = _pixel(image, gate.global_position + Vector2(-250, 0))
		check(Vector3(plaza_pixel.r - path_pixel.r, plaza_pixel.g - path_pixel.g, plaza_pixel.b - path_pixel.b).length() < 0.012, "GPU plaza and path have matching colours")
		var original: ShaderMaterial = (gate.get_node("Presentation").get("plate") as Sprite2D).material as ShaderMaterial
		player.hide()
		var split: Image = await _frame()
		split.save_png(OUT + "split_pillars.png")
		original.set_shader_parameter(&"hide_pillars", false)
		platform.hide()
		var whole: Image = await _frame()
		whole.save_png(OUT + "whole_sprite.png")
		check(split.get_data() == whole.get_data(), "Separating the pillars preserves every source pixel")
		original.set_shader_parameter(&"hide_pillars", true)
		platform.show()
		player.show()
		var first_pillar: Node2D = pillars[0] as Node2D
		var first_foot: Vector2 = (first_pillar.get_node("SolidBase") as Node2D).global_position
		_place(player, first_foot + Vector2(0, -13))
		image = await _frame()
		image.save_png(OUT + "behind_pillar.png")
		_place(player, first_foot + Vector2(0, 14))
		image = await _frame()
		image.save_png(OUT + "in_front_of_pillar.png")
	check(FileAccess.get_sha256("res://monster_booster.ldtk") == map_hash, "Runtime leaves the LDtk authoring unchanged")
	print("CENTRAL_WARP_PHYSICS_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
