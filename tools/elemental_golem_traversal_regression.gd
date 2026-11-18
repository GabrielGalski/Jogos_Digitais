extends SceneTree
## Exercise real dash physics and golem leaps against the currently painted islands.
const SCENE: PackedScene = preload("res://scenes/bosses/elemental_golem_arena.tscn")
const BOSS: Script = preload("res://scripts/bosses/elemental_golem/elemental_golem.gd")
var failures: Array[String] = []
var arena: Node2D = null
var player: Player = null
var layout: Node2D = null
var boss: Node2D = null
var capture: bool = false


func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)


func wait_until(condition: Callable, seconds: float = 3.0) -> bool:
	var limit: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < limit: await process_frame
	return bool(condition.call())


func settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func dash_between(from: Vector2, direction: Vector2, destination: int) -> void:
	player.position = layout.to_global(from) - Vector2(0, 3)
	player.reset_physics_interpolation()
	player.impact_control_lock = 0.0
	player.dash_remaining = 0.0
	player.dash_charges = Player.MAX_DASH_CHARGES
	await settle()
	var health: float = player.health
	check(player.try_dash(direction), "Dash begins")
	check(await wait_until(func() -> bool: return not player.is_dashing()), "Dash completes")
	await settle()
	check(is_equal_approx(player.health, health), "Crossing a lateral gap doesn't cost health")
	check(int(layout.call("platform_at", player.to_global(Vector2(0, 3)))) == destination,
		"Dash lands on destination platform " + str(destination))


func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	var source_hash: String = FileAccess.get_sha256("res://monster_booster.ldtk")
	arena = SCENE.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	layout = arena.get_node("CastleLayout") as Node2D
	boss = arena.get_node("ElementalGolem") as Node2D
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))), "Arrival completes")
	boss.set_physics_process(false)
	check(bool(layout.get("adapted_to_painted_floor")), "Current redraw is reconciled in memory")
	check(is_equal_approx(player.dash_speed * player.dash_duration, 128.0), "Arena dash covers 128 pixels")
	var normal_player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	check(is_equal_approx(normal_player.dash_duration * normal_player.dash_speed, 105.6), "Shared dash balance remains available outside this arena")
	normal_player.free()
	var platforms: Array = layout.get("platforms") as Array
	for row: int in range(3):
		var middle: Rect2 = platforms[row * 3 + 1] as Rect2
		var left: Rect2 = platforms[row * 3] as Rect2
		var right: Rect2 = platforms[row * 3 + 2] as Rect2
		var y: float = left.get_center().y
		await dash_between(Vector2(middle.position.x + 14, y), Vector2.LEFT, row * 3)
		await dash_between(Vector2(left.end.x - 14, y), Vector2.RIGHT, row * 3 + 1)
		await dash_between(Vector2(middle.end.x - 14, y), Vector2.RIGHT, row * 3 + 2)
		await dash_between(Vector2(right.position.x + 14, y), Vector2.LEFT, row * 3 + 1)
	# A genuine missed dash into an inter-row void still uses one-block recovery.
	var first: Rect2 = platforms[0] as Rect2
	player.position = layout.to_global(first.get_center()) - Vector2(0, 3)
	await settle()
	var health: float = player.health
	player.position = layout.to_global(Vector2(first.get_center().x, first.end.y + 8)) - Vector2(0, 3)
	check(await wait_until(func() -> bool: return player.health < health), "Void remains hazardous")
	check(is_equal_approx(player.health, health - player.max_health / 6.0), "Void costs exactly one health block")
	player.heal_full()
	player.grant_fall_recovery(60.0)
	# Let actual jump/landing states run for all nine regions, then a natural cycle.
	boss.set_physics_process(true)
	for index: int in range(9):
		boss.call("_jump_to", index, false)
		check(await wait_until(func() -> bool: return int(boss.get("state")) == BOSS.State.LANDING), "Golem completes leap " + str(index))
		check(int(layout.call("platform_at", boss.global_position)) == index, "Golem lands on the requested floor region")
		check(bool(layout.call("supports_feet", boss.global_position)), "Golem destination has actual visible floor")
	boss.set("walk_speed", 1000.0)
	boss.set("barrage_duration", 0.3)
	check(await wait_until(func() -> bool: return (boss.get("barrage_history") as Array).size() >= 4, 12.0), "Golem alternates platforms through natural attack cycles")
	var history: Array = boss.get("barrage_history") as Array
	for index: int in range(1, history.size()):
		check(history[index] != history[index - 1], "No repeated firing platform")
	if capture:
		var camera: Camera2D = player.get_node("Camera2D") as Camera2D
		player.position = layout.to_global((platforms[3] as Rect2).get_center())
		camera.reset_smoothing()
		camera.force_update_scroll()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/elemental_golem/traversal_runtime.png")
	check(FileAccess.get_sha256("res://monster_booster.ldtk") == source_hash, "LDtk remains byte-for-byte unchanged")
	arena.queue_free()
	await process_frame
	print("ELEMENTAL_GOLEM_TRAVERSAL_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)
