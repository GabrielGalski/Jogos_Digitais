extends SceneTree
## The four idle shooter positions follow the four mouse corners around Nox.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/dungeon/merchant_platform.tscn")
	await create_timer(0.5).timeout
	var room: Node2D = current_scene as Node2D
	var player: Player = room.get_node("Nox") as Player
	var gun: Node2D = player.get_node("BoosterShooter") as Node2D
	var companion: Node2D = gun.get("companion") as Node2D
	(room.get_node("ManifestationController") as Node).set_physics_process(false)
	gun.set_process(false)
	player.intro_locked = false
	check(is_instance_valid(companion), "Shooter companion was not created")
	if is_instance_valid(companion):
		var corners: Array[Vector2] = [
			Vector2(-100.0, -100.0),
			Vector2(100.0, -100.0),
			Vector2(-100.0, 100.0),
			Vector2(100.0, 100.0),
		]
		for corner: Vector2 in corners:
			var target_world: Vector2 = player.global_position + corner
			gun.set("aim_screen_override", room.get_viewport().get_canvas_transform() * target_world)
			companion.set("initialized", false)
			companion.set("crossing_time", 0.0)
			companion.call("update_pose", 0.4)
			var offset: Vector2 = companion.global_position - player.global_position
			check(offset.x * corner.x > 0.0, "wrong horizontal quadrant for " + str(corner))
			check(offset.y * corner.y > 0.0, "wrong vertical quadrant for " + str(corner))
	print("SHOOTER QUADRANTS REGRESSION: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
