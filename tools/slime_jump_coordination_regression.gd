extends SceneTree
## Dense simultaneous attacks at a thin terrain corner: bounded motion and spaced landings.
const PACK: Script = preload("res://scripts/enemies/slime_pack.gd")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const OUT: String = "res://output/slime_jumps/"
var world: Node2D = null
var player: Player = null
var actors: Array[CharacterBody2D] = []
var failures: Array[String] = []
var report: Dictionary = {}
var checks: int = 0
var rendered: bool = false
var corner: Rect2 = Rect2(776, 788, 12, 7)


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	if "--slow-physics" in OS.get_cmdline_user_args(): Engine.physics_ticks_per_second = 30
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if value: return
	failures.append(message)
	push_error("[SLIME_JUMPS] " + message)


func frames(count: int) -> void:
	for index: int in range(count): await physics_frame


func capture(label: String) -> void:
	if not rendered: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + label + ".png")


func supported(point: Vector2) -> bool:
	return not corner.has_point(point) and Rect2(480, 480, 640, 640).has_point(point)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(480, 270)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	player = PLAYER.instantiate() as Player
	player.arena_bounds = Rect2(480, 480, 640, 640)
	player.movement_bounds = player.arena_bounds
	world.add_child(player)
	player.position = Vector2(800, 800)
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	player.get_node("BoosterShooter").set_process(false)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.35
	camera.force_update_scroll()
	for group_index: int in range(3):
		var pack: Node2D = PACK.new() as Node2D
		world.add_child(pack)
		var starts: Array[Vector2] = []
		for index: int in range(5):
			var angle: float = (group_index * 5 + index) * TAU / 15.0
			starts.append(player.position + Vector2.from_angle(angle) * 84.0)
		pack.call("configure", starts[0], starts, player, FlyingEyeProfile.new(), supported, Callable(), 224.0, 192.0, group_index * 0.17)
		for actor: CharacterBody2D in pack.get("members") as Array:
			actor.set("_cooldown", 0.0)
			actors.append(actor)
	var neighbors: Array[Node2D] = []
	for actor: CharacterBody2D in actors: neighbors.append(actor)
	for actor: CharacterBody2D in actors: (actor.get("squad") as Node2D).set("neighbors", neighbors)
	await frames(2)
	var maximum_airborne: int = 0
	var maximum_ground_speed: float = 0.0
	var maximum_step: float = 0.0
	var maximum_distance: float = 0.0
	var landing_overlaps: int = 0
	var corner_steps: int = 0
	var last_positions: Dictionary[int, Vector2] = {}
	var last_landings: Dictionary[int, int] = {}
	var captured_windup: bool = false
	var captured_impact: bool = false
	for actor: CharacterBody2D in actors:
		last_positions[actor.get_instance_id()] = actor.global_position
		last_landings[actor.get_instance_id()] = int(actor.get("landings"))
	for tick: int in range(Engine.physics_ticks_per_second * 20):
		await frames(1)
		var airborne: int = 0
		for actor: CharacterBody2D in actors:
			var identifier: int = actor.get_instance_id()
			var state: int = int(actor.get("state"))
			if state == 2: airborne += 1
			elif tick > 2: maximum_ground_speed = maxf(maximum_ground_speed, actor.velocity.length())
			maximum_step = maxf(maximum_step, actor.global_position.distance_to(last_positions[identifier]))
			maximum_distance = maxf(maximum_distance, actor.global_position.distance_to(player.global_position))
			if corner.has_point(actor.global_position): corner_steps += 1
			last_positions[identifier] = actor.global_position
			if int(actor.get("landings")) > last_landings[identifier]:
				for other: CharacterBody2D in actors:
					if other == actor or int(other.get("state")) == 2: continue
					if actor.global_position.distance_to(other.global_position) < 13.5: landing_overlaps += 1
				last_landings[identifier] = int(actor.get("landings"))
				if not captured_impact:
					captured_impact = true
					await capture("impact_only")
			if state == 1 and not captured_windup:
				captured_windup = true
				await capture("windup_without_circle")
		maximum_airborne = maxi(maximum_airborne, airborne)
	var total_jumps: int = 0
	var least_jumps: int = 100000
	for actor: CharacterBody2D in actors:
		var count: int = int(actor.get("jumps_started"))
		total_jumps += count
		least_jumps = mini(least_jumps, count)
	check(maximum_airborne <= 1, "One Slime is airborne at a time across nearby packs")
	check(maximum_ground_speed <= 100.0, "Ground states never inherit flight velocity")
	check(maximum_step <= 360.0 / Engine.physics_ticks_per_second + 2.0 and maximum_distance < 240.0, "Crowded jumps never fling a Slime away or outside its encounter")
	check(landing_overlaps == 0, "Landings stay clear of other Slime bodies")
	check(corner_steps == 0, "Jump and retreat motion still respect the dry terrain boundary")
	check(least_jumps >= 1 and total_jumps >= 20, "All fifteen Slimes receive turns and keep attacking")
	var coordinator: Node = (actors[0].get("squad") as Node2D).get("jump_coordinator") as Node
	var active: CharacterBody2D = null
	for tick: int in range(90):
		for actor: CharacterBody2D in actors:
			if int(actor.get("state")) == 2: active = actor
		if active != null: break
		await frames(1)
	check(active != null, "Stress fixture has a live jump to interrupt")
	if active != null:
		var identifier: int = active.get_instance_id()
		active.call("take_damage", 999.0)
		check(not (coordinator.get("reservations") as Dictionary).has(identifier), "Dying mid-jump immediately releases the turn and landing reservation")
	var before_next: int = 0
	for actor: CharacterBody2D in actors:
		if bool(actor.call("is_alive")): before_next += int(actor.get("jumps_started"))
	player.position += Vector2(40, -20)
	player.reset_physics_interpolation()
	await frames(120)
	var after_next: int = 0
	for actor: Node in get_nodes_in_group(&"slimes"): after_next += int(actor.get("jumps_started"))
	check(after_next > before_next, "The queue continues after an airborne Slime dies and the player moves")
	for node: Node in world.get_children():
		if node.has_method("set_suspended"): node.call("set_suspended", true)
	check((coordinator.get("reservations") as Dictionary).is_empty() and (coordinator.get("_waiting") as Array).is_empty(), "Altar-style suspension clears all pending jumps")
	report = {"checks": checks, "max_airborne": maximum_airborne, "max_ground_speed": maximum_ground_speed, "max_step_px": maximum_step, "max_distance_px": maximum_distance,
		"landing_overlaps": landing_overlaps, "corner_steps": corner_steps, "total_jumps": total_jumps, "least_jumps": least_jumps, "failures": failures}
	var report_name: String = "coordination_30hz.json" if Engine.physics_ticks_per_second == 30 else "coordination.json"
	var output: FileAccess = FileAccess.open(OUT + report_name, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("SLIME_JUMP_COORDINATION ", "PASS" if failures.is_empty() else "FAIL", " ", JSON.stringify(report))
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
