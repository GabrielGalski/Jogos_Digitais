extends SceneTree

func _initialize() -> void:
	call_deferred("check_scene")

func check_scene() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena = main.get_node("TutorialArena")
	await arena.entrance_finished
	var throne = arena.get_node("MinotaurChair")
	var sprite: AnimatedSprite2D = throne.get_node("Asterion")
	assert(sprite.is_playing())
	assert(throne.get_node("Back").visible and throne.get_node("Seat").visible)
	assert(sprite.sprite_frames.get_frame_count("sitting") == 3)
	var seen_frames = {}
	var seen_textures = {}
	for i in range(30):
		seen_frames[sprite.frame] = true
		var chain = arena.get_node("Chain3")
		assert(chain.get_node("AnimationPlayer").is_playing())
		assert(chain.get_node("Sprite").texture == chain.get_node("DepthSprite").texture)
		seen_textures[chain.get_node("Sprite").texture.resource_path] = true
		await create_timer(0.08).timeout
	assert(seen_frames.size() == 3)
	assert(seen_textures.size() >= 8)
	var floor_layer: TileMapLayer = arena.get_node("Floor")
	var hole: CollisionPolygon2D = arena.get_node("ArenaCollision/SmallHoleBoundary")
	var empty_count = 0
	for y in range(17,24):
		for x in range(26,37):
			var cell = Vector2i(x,y)
			var center = floor_layer.position + floor_layer.map_to_local(cell)
			var inside = Geometry2D.is_point_in_polygon(center,hole.polygon)
			var empty = floor_layer.get_cell_source_id(cell) == -1
			assert(inside == empty, "Crater floor/collision mismatch at " + str(cell))
			if empty: empty_count += 1
	assert(empty_count > 0)
	assert(floor_layer.get_used_rect() == Rect2i(0,0,42,35))
	assert(arena.get_node("Chain3").position == Vector2(144,32))
	print("PASS: crater cutout matches collision; chains animate across ",seen_textures.size()," textures; Asterion cycles all three frames; intro completes.")
	if DisplayServer.get_name() != "headless":
		arena.get_node("Mox/Camera2D").enabled = false
		var camera := Camera2D.new()
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		arena.add_child(camera)
		camera.position = Vector2(0,-40)
		camera.zoom = Vector2(0.4,0.4)
		camera.make_current()
		await create_timer(0.2).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/tutorial_asterion_overview.png")
		camera.position = Vector2(144,-28)
		camera.zoom = Vector2(3,3)
		await create_timer(0.2).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/tutorial_crater_detail.png")
		camera.position = Vector2(0,-250)
		await create_timer(0.2).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/tutorial_asterion_detail.png")
	quit()
