extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	var packed: PackedScene = load("res://scenes/merchant_corridor.tscn") as PackedScene
	var hall: Node2D = packed.instantiate() as Node2D
	root.add_child(hall)
	await create_timer(2.8).timeout
	var camera: Camera2D = hall.get_node("RoomCamera") as Camera2D
	assert(is_equal_approx(root.get_visible_rect().size.y / camera.zoom.y, 334.0))
	assert(hall.get_node("World/Toldo/Visual") is Sprite2D)
	assert((hall.get_node("Nox/Visual") as AnimatedSprite2D).scale == Vector2(2.1, 2.1))
	assert(hall.get("state") == 2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://renders")
	root.get_texture().get_image().save_png("res://renders/merchant_presentation_left.png")
	hall.set("ground_position", Vector2(500.0, 28.0))
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://renders/merchant_presentation_center.png")
	hall.set("ground_position", Vector2(950.0, 28.0))
	await create_timer(3.5).timeout
	assert(hall.get("state") == 2)
	assert((hall.get("ground_position") as Vector2).x < 100.0)
	print("MERCHANT PRESENTATION PASS: full height, Nox scale, awning instance, entrance and exit fade/reset")
	quit()
