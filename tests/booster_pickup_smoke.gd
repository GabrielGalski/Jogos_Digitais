extends SceneTree


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var controller := main.get_node("BoosterDropPreview") as BoosterDropPreview
	var player := main.get_node("Player") as Player
	controller.set_process(false)
	player.set_physics_process(false)

	var pickup := controller.get_current_pickup()
	if not is_instance_valid(pickup):
		_fail("the fixed booster pickup should spawn when the arena starts")
		return
	if pickup.global_position != Vector2(52.0, 24.0):
		_fail("the visual-study booster should use the configured fixed point")
		return
	var sprite := pickup.get_node("Sprite") as Sprite2D
	if not sprite.scale.is_equal_approx(Vector2(0.0625, 0.0625)):
		_fail("the ground booster should be seventy-five percent smaller than its previous scale")
		return
	if sprite.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
		_fail("the ground booster should use the same bilinear filter as the weapon")
		return
	if sprite.texture.get_size() != Vector2(128.0, 128.0):
		_fail("the pickup should use the rebuilt booster_dropped sprite")
		return
	if pickup.collision_layer != 0 or pickup.collision_mask != 1:
		_fail("the booster should detect only the Player without blocking movement")
		return

	player.global_position = pickup.global_position + Vector2(15.0, 0.0)
	pickup.call(&"_physics_process", 0.016)
	if not pickup.is_collected() or not pickup.is_queued_for_deletion():
		_fail("walking near the booster should collect and remove it")
		return
	if not is_equal_approx(controller.get_respawn_remaining(), 10.0):
		_fail("collection should start an exact ten-second visual respawn")
		return

	controller.call(&"_process", 9.9)
	if is_instance_valid(controller.get_current_pickup()):
		_fail("the booster should remain absent before ten seconds")
		return
	controller.call(&"_process", 0.11)
	var respawned := controller.get_current_pickup()
	if not is_instance_valid(respawned) or respawned.is_queued_for_deletion():
		_fail("the booster should reappear after ten seconds")
		return
	if respawned.global_position != Vector2(52.0, 24.0):
		_fail("the booster should always return to the same fixed point")
		return

	print("BOOSTER_PICKUP_SMOKE_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
