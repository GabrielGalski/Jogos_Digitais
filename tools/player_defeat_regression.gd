extends SceneTree
## Exercise real fatal damage, modal input, checkpoint reload and global-clock cleanup.

var failures: Array[String] = []
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func wait_until(condition: Callable, seconds: float = 4.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://output/player_defeat")
	root.get_texture().get_image().save_png("res://output/player_defeat/" + label + ".png")


func _run() -> void:
	root.size = Vector2i(960, 540)
	for scene_path: String in ["res://scenes/dungeon/ldtk_arena.tscn", "res://scenes/tutorial_arena.tscn"]:
		var room: Node = (load(scene_path) as PackedScene).instantiate()
		root.add_child(room)
		current_scene = room
		var player: Player = room.get_node("Nox" if room.has_node("Nox") else "Mox") as Player
		check(await wait_until(func() -> bool: return not player.intro_locked), "Arrival finishes")
		var spawn: Vector2 = player.global_position
		var defeat: CanvasLayer = room.get_node("PlayerDefeat") as CanvasLayer
		var original_runtime: CardCombatRuntime = player.get_node("BoosterShooter").get("card_runtime") as CardCombatRuntime
		if room.has_node("SpiritHordes"):
			var encounters: Array = room.get_node("SpiritHordes").get("encounters") as Array
			encounters[0].call("begin")
		else:
			var encounter: Node = room.get_node("MinotaurChair/TutorialEncounter")
			encounter.call("skip_to_boss")
			check(await wait_until(func() -> bool: return not player.intro_locked), "Boss combat unlocks before fatal hit")
		player.global_position += Vector2(48, -16)
		player.receive_skybreaker_hit(999.0)
		check(await wait_until(func() -> bool: return bool(defeat.get("active"))), "Fatal damage starts cinematic")
		check(is_equal_approx(Engine.time_scale, 0.12), "World runs at twelve percent speed")
		check(player.dead and player.intro_locked, "Dead player cannot move or attack")
		check(player.body.material is ShaderMaterial, "Player uses white silhouette shader")
		await create_timer(0.4, true, false, true).timeout
		check(float(defeat.get_node("DiagonalSlash").get("progress")) > 0.0, "Diagonal slash crosses silhouette")
		await capture("slash_" + room.name)
		check(await wait_until(func() -> bool: return bool(defeat.get("menu_ready"))), "Retry menu appears in real time")
		check(paused, "Encounter pauses at end of cinematic")
		var camera: Camera2D = root.get_camera_2d()
		check(camera.global_position.distance_to(player.body.global_position) < 1.0, "Death camera centers on player")
		var button: Button = defeat.get_node("RetryMenu/Content/Retry") as Button
		check(button.has_focus(), "Retry supports keyboard focus")
		check(button.text == "Tentar Novamente", "Retry label matches requested copy")
		await capture("menu_" + room.name)
		# Real keyboard events exercise the button while the world is paused.
		var press: InputEventAction = InputEventAction.new()
		press.action = &"ui_accept"
		press.pressed = true
		Input.parse_input_event(press)
		await process_frame
		press = InputEventAction.new()
		press.action = &"ui_accept"
		press.pressed = false
		Input.parse_input_event(press)
		var old_id: int = room.get_instance_id()
		check(await wait_until(func() -> bool: return current_scene != null and current_scene.get_instance_id() != old_id), "Retry replaces encounter")
		check(is_equal_approx(Engine.time_scale, 1.0) and not paused, "Retry restores clock and unpauses")
		var fresh: Node = current_scene
		check(fresh.scene_file_path == scene_path, "Retry stays in checkpoint scene")
		var revived: Player = fresh.get_node("Nox" if fresh.has_node("Nox") else "Mox") as Player
		check(revived.global_position.is_equal_approx(spawn), "Retry returns to arrival warp, not death location")
		check(revived.health == revived.max_health and not revived.dead, "Retry restores full health")
		if fresh.has_node("SpiritHordes"):
			var restarted_hordes: Array = fresh.get_node("SpiritHordes").get("encounters") as Array
			check(int(restarted_hordes[0].get("defeated_count")) == 0, "Retry resets horde progress")
		check(revived.get_node("BoosterShooter").get("card_runtime") != original_runtime, "Retry uses clean card runtime")
		check(await wait_until(func() -> bool: return not revived.intro_locked), "Arrival cutscene unlocks revived player")
		# A second defeat must work; external scene teardown must not leak pause/slow motion.
		revived.receive_skybreaker_hit(999.0)
		check(await wait_until(func() -> bool: return bool(fresh.get_node("PlayerDefeat").get("menu_ready"))), "Repeated death works")
		fresh.queue_free()
		await process_frame
		await process_frame
		check(is_equal_approx(Engine.time_scale, 1.0) and not paused, "External teardown restores clock")
	print("PLAYER_DEFEAT_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)
