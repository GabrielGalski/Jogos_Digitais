extends SceneTree

const NAV: Script = preload("res://scripts/enemies/ground_horde_navigation.gd")
const CATALOG: Script = preload("res://scripts/enemies/open_world_horde_catalog.gd")
const REGION: Script = preload("res://scripts/dungeon/pedestal_arena_region.gd")
var failures: Array[String] = []
var metrics: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame


func _fixture() -> void:
	var fixture: Node2D = Node2D.new()
	fixture.position = Vector2(10000, 10000)
	root.add_child(fixture)
	var wall: StaticBody2D = StaticBody2D.new()
	var collider: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(32, 48)
	collider.shape = rectangle
	wall.position = Vector2(72, 0)
	wall.add_child(collider)
	fixture.add_child(wall)
	var actor: CharacterBody2D = CharacterBody2D.new()
	actor.collision_layer = 4
	actor.collision_mask = 1
	var body: CircleShape2D = CircleShape2D.new()
	body.radius = 7.0
	var body_shape: CollisionShape2D = CollisionShape2D.new()
	body_shape.shape = body
	actor.add_child(body_shape)
	actor.position = Vector2(-136, 60)
	fixture.add_child(actor)
	await ticks(2)
	var nav: NAV = NAV.new()
	var ground: Callable = func(point: Vector2) -> bool:
		var local: Vector2 = fixture.to_local(point)
		return Rect2(-160, -112, 320, 224).has_point(local) and (absf(local.x) >= 24.0 or absf(local.y) < 24.0)
	nav.configure(Rect2(-160, -112, 320, 224), fixture, ground)
	nav.sample_cells()
	var target: Vector2 = Vector2(136, 60)
	nav.update_target(target)
	check(nav.distances.has(nav.cell(actor.position)), "Bridge links both shores around the solid obstacle")
	var unsafe: int = 0
	for index: int in range(540):
		var desired: Vector2 = actor.position.direction_to(nav.waypoint(actor.position, target))
		actor.velocity = nav.steer(actor.position, desired) * 60.0
		actor.move_and_slide()
		if not nav.has_floor(actor.position):
			unsafe += 1
		if actor.position.distance_to(target) < 12.0:
			break
		await physics_frame
	check(actor.position.distance_to(target) < 12.0, "Mob crosses the narrow bridge and goes around a solid obstacle")
	check(unsafe == 0, "Full collision footprint stays on dry ground")
	metrics.append({"fixture_end": str(actor.position), "unsafe": unsafe})
	fixture.queue_free()
	await ticks(2)


func _check_retarget(encounter: Node2D, navigation: NAV, player: Player, totem: Node2D, id: String) -> void:
	var start: Vector2 = encounter.to_local(player.global_position)
	var portal: Vector2 = encounter.to_local(totem.global_position)
	var region: Dictionary = encounter.get("arena_region") as Dictionary
	var destination: Vector2 = REGION.clamp_motion(region, start, portal + Vector2(144, 176), 14.0)
	var initial_goal: Vector2i = navigation.goal
	check(start.distance_to(destination) > 64.0, id + " has space to move away from the altar")
	var following: Dictionary[Node2D, float] = {}
	for actor: Node2D in encounter.get("actors") as Array:
		var distance: float = actor.position.distance_to(destination)
		if actor.position.distance_to(portal) < 140.0 and distance > float(actor.get("stats").reach) + 16.0:
			following[actor] = distance
	player.global_position = encounter.to_global(destination)
	player.snap_floor_height()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	await ticks(240)
	check(navigation.goal != initial_goal and navigation.center(navigation.goal).distance_to(destination) < 20.0,
		id + " rebuilds the flow toward Nox after moving below and to the right of the altar")
	var followed: int = 0
	for actor: Node2D in following:
		if is_instance_valid(actor) and float(following[actor]) - actor.position.distance_to(destination) >= 32.0:
			followed += 1
	check(followed > 0, id + " enemies already at the altar leave to pursue the new position")
	metrics.append({"id": id, "target_shift_px": start.distance_to(destination), "left_altar": followed, "tracked": following.size()})


func _run() -> void:
	await _fixture()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 19
	var roles: Dictionary = {"melee": 0, "ranged": 0, "support": 0}
	for index: int in range(6000):
		var species: String = CATALOG.pick("room_2_castle_west", 5.0, random)
		var role: String = str(CATALOG.TYPES[species].role)
		roles[role] += 1
	check(int(roles.support) > int(roles.ranged) and int(roles.ranged) > int(roles.melee), "Support > ranged > melee weighted population")
	check(CATALOG.TYPES[CATALOG.pick("room_2_castle_west", 0.0, random)].role == "support", "Support enters first")
	var world: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	world.set("warp_entry_cutscene_enabled", false)
	root.add_child(world)
	while not bool(world.get("entry_complete")):
		await process_frame
	var player: Player = world.get_node("Nox") as Player
	player.contact_invulnerability = 1000.0
	var totems: Array = world.get_node("HordePedestals").get("pedestals") as Array
	var duration_test: bool = "--duration" in OS.get_cmdline_user_args()
	if duration_test:
		totems = [totems.front()]
	for totem: Node2D in totems:
		var encounter: Node2D = totem.get("encounter") as Node2D
		(encounter.get("profile") as Resource).set("miniboss_spawn_chance", 0.0)
		player.global_position = totem.global_position + Vector2(40, 12)
		player.velocity = Vector2.ZERO
		player.snap_floor_height()
		var camera: Camera2D = player.get_node("Camera2D") as Camera2D
		camera.reset_smoothing()
		camera.force_update_scroll()
		await ticks(2)
		encounter.call("begin")
		check(int(encounter.get("phase")) == 1, "Real totem activates")
		for frame: int in range(1200):
			if int(encounter.get("_opening_remaining")) <= 0:
				break
			await ticks(1)
		check(int(encounter.get("_opening_remaining")) == 0, "Opening wave finishes spawning")
		var ids: Dictionary = {}
		var navigation: NAV = encounter.get("ground_navigation") as NAV
		for actor: Node2D in encounter.get("actors") as Array:
			ids[actor.get_instance_id()] = int(navigation.distances.get(navigation.cell(actor.position), 1000000))
		var peak_actors: int = 0
		var peak_projectiles: int = 0
		for index: int in range(2390 if duration_test else 720):
			await ticks(1)
			peak_actors = maxi(peak_actors, (encounter.get("actors") as Array).size())
			peak_projectiles = maxi(peak_projectiles, (encounter.get("projectiles") as Array).size())
		var unsafe: int = 0
		var arrived: int = 0
		var stalled: int = 0
		var overlaps: int = 0
		var live: Array = encounter.get("actors") as Array
		for actor: Node2D in live:
			if not navigation.has_floor(actor.position):
				unsafe += 1
			var distance: float = actor.global_position.distance_to(player.global_position)
			if ids.has(actor.get_instance_id()):
				var route_remaining: int = int(navigation.distances.get(navigation.cell(actor.position), 1000000))
				if route_remaining < int(ids[actor.get_instance_id()]) - 10:
					arrived += 1
				elif distance > float(actor.get("stats").reach) + 32.0:
					stalled += 1
			for other: Node2D in live:
				if actor.get_instance_id() < other.get_instance_id() and actor.position.distance_to(other.position) < 8.0:
					overlaps += 1
		var id: String = str(encounter.get("encounter_id"))
		metrics.append({"id": id, "alive": live.size(), "initial_progress": arrived, "initial_stalled": stalled,
			"unsafe": unsafe, "overlapping_pairs": overlaps, "peak_actors": peak_actors, "peak_projectiles": peak_projectiles})
		check(live.size() >= 36 and live.size() <= int(encounter.get("profile").open_world_maximum_alive), id + " respects the live enemy budget")
		check(peak_actors <= 48 and peak_projectiles <= 96, id + " stays within both budgets throughout combat")
		check(unsafe == 0, id + " mobs stay on actual riverbanks and bridges")
		check(arrived > 0 and stalled == 0, id + " initial recruits navigate to combat range")
		check(overlaps <= maxi(2, int(float(live.size()) / 20.0)), id + " avoids deeply overlapping bodies")
		if not duration_test:
			await _check_retarget(encounter, navigation, player, totem, id)
			encounter.set("_elapsed", 39.99)
		var before_pause: float = float(encounter.get("elapsed_seconds"))
		paused = true
		await ticks(4)
		check(is_equal_approx(float(encounter.get("elapsed_seconds")), before_pause), id + " timer pauses with gameplay")
		paused = false
		await ticks(20 if duration_test else 2)
		check(int(encounter.get("phase")) == 2 and encounter.get("completion_reason") == &"time", id + " timer clears the encounter")
		check((encounter.get("actors") as Array).is_empty(), id + " clears every survivor")
		await ticks(16)
	world.queue_free()
	await ticks(2)
	DirAccess.make_dir_recursive_absolute("res://output/horde_totems")
	var report: FileAccess = FileAccess.open("res://output/horde_totems/navigation-regression.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures": failures, "metrics": metrics, "roles": roles}, "\t"))
	print("GROUND_HORDE_NAVIGATION ", JSON.stringify({"failures": failures, "metrics": metrics, "roles": roles}))
	quit(0 if failures.is_empty() else 1)
