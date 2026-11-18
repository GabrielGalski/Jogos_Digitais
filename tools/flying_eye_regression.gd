extends SceneTree
## Visual-only hover/recoil, real pack simulation, swept orbs and LDtk integration.

const EYE: Script = preload("res://scripts/enemies/flying_eye.gd")
const PACK: Script = preload("res://scripts/enemies/flying_eye_pack.gd")
const ORB: Script = preload("res://scripts/combat/projectiles/flying_eye_orb.gd")
const ZONES: Script = preload("res://scripts/dungeon/flying_eye_zones.gd")
const AFFILIATION: Script = preload("res://scripts/combat/combat_affiliation.gd")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
var failures: Array[String] = []
var checks: int = 0
var world: Node2D = null
var player: Player = null
var rendered: bool = false
var report: Dictionary = {}


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("[FLYING EYE] " + message)


func frames(count: int) -> void:
	for index: int in range(count): await physics_frame


func fixture_player() -> void:
	world = Node2D.new()
	root.add_child(world)
	player = PLAYER.instantiate() as Player
	player.arena_bounds = Rect2(-1000, -1000, 6000, 6000)
	player.movement_bounds = player.arena_bounds
	world.add_child(player)
	player.position = Vector2(800, 800)
	player.set_physics_process(false)
	player.get_node("BoosterShooter").set_process(false)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE
	camera.force_update_scroll()


func eye_at(point: Vector2) -> CharacterBody2D:
	var eye: CharacterBody2D = EYE.new() as CharacterBody2D
	world.add_child(eye)
	eye.position = point
	eye.set_physics_process(false)
	return eye


func pack_at(center: Vector2, count: int, ring: float = 92.0) -> Node2D:
	var starts: Array[Vector2] = []
	for index: int in range(count): starts.append(center + Vector2.from_angle(index * TAU / count) * ring)
	var pack: Node2D = PACK.new() as Node2D
	world.add_child(pack)
	pack.call("configure", center, starts, player, FlyingEyeProfile.new(),
		func(_point: Vector2) -> bool: return true, Callable(), 264.0, 192.0, 0.0)
	var neighbors: Array[Node2D] = []
	for eye: Node2D in pack.get("members") as Array: neighbors.append(eye)
	pack.set("neighbors", neighbors)
	return pack


func orb_at(point: Vector2, heading: Vector2 = Vector2.RIGHT, source: Node2D = null) -> Node2D:
	var orb: Node2D = ORB.new() as Node2D
	orb.set("target", player)
	orb.set("shooter", source)
	orb.set("direction", heading)
	world.add_child(orb)
	orb.position = point
	orb.set_physics_process(false)
	return orb


func _visual_and_health() -> void:
	var eye: CharacterBody2D = eye_at(Vector2(700, 800))
	var visual: Sprite2D = eye.get("visual") as Sprite2D
	visual.set_process(false)
	visual.set("phase", 0.0)
	visual.set("_age", 0.0)
	visual.call("_update_visual", 0.0)
	var origin: Vector2 = eye.position
	check(is_equal_approx(visual.texture.get_width() * visual.scale.x, 16.0), "Visible idle body is 16 px")
	visual.call("_update_visual", 0.55)
	check(is_equal_approx(float(visual.get("hover_offset")), 1.25) and is_zero_approx(visual.position.x), "Idle floats on the vertical axis")
	eye.call("shoot_recoil", Vector2.RIGHT)
	visual.call("_update_visual", 0.0)
	check(visual.position.x < -2.3 and eye.position == origin, "Shot recoil is opposite to aim and never moves the collider")
	visual.call("_update_visual", 0.15)
	check(is_zero_approx(visual.position.x), "Short recoil recovers to its own axis")
	check(is_equal_approx(float(eye.call("get_current_health")), 6.0), "Eye starts with six HP")
	eye.call("take_damage", 3.0)
	check(bool(eye.call("is_alive")) and is_equal_approx(float(eye.call("get_current_health")), 3.0), "First base-three hit leaves three HP")
	eye.call("take_damage", 3.0)
	check(not bool(eye.call("is_alive")) and eye.collision_layer == 0 and not eye.is_in_group("enemy_bodies"), "Second base-three hit ends combat immediately")
	var seen: Dictionary[int, bool] = {}
	for index: int in range(10):
		visual.set("_death_age", float(index) / 16.0)
		visual.call("_update_visual", 0.0)
		seen[visual.texture.get_instance_id()] = true
		check(visual.texture.get_size() == Vector2(96, 80) and visual.offset == Vector2(0, 3), "Death frame %d preserves canvas and common pivot" % index)
	check(seen.size() == 10, "Death uses ten distinct cropped frames")
	visual.call("_update_visual", 0.08)
	await frames(2)
	check(not is_instance_valid(eye), "Actor is freed after the death animation")


func _packs() -> void:
	player.contact_invulnerability = 1000.0
	for size: int in range(2, 6):
		var pack: Node2D = pack_at(player.position, size)
		await frames(2)
		check((pack.get("members") as Array).size() == size and (pack.get("_slot_order") as Dictionary).size() == size, "Distinct formation slots for %d eyes" % size)
		if size < 5:
			pack.call("dismiss")
			await frames(2)
			continue
		await frames(480)
		var shot_history: Array = pack.get("attack_log") as Array
		check(shot_history.size() >= 9, "Stationary pack cycles several full volleys")
		var turns_ok: bool = true
		for index: int in range(shot_history.size()):
			if int(shot_history[index].shot) != index % 3 + 1: turns_ok = false
			if index % 3 != 0 and int(shot_history[index].actor) != int(shot_history[index - 1].actor): turns_ok = false
			if index % 3 == 0 and index >= 3 and int(shot_history[index].actor) == int(shot_history[index - 1].actor): turns_ok = false
		check(turns_ok, "One member fires exactly three shots before yielding the attack turn")
		var recoil_total: int = 0
		var smallest: float = INF
		var highest_speed: float = 0.0
		var members: Array = pack.get("members") as Array
		for a: CharacterBody2D in members:
			recoil_total += int((a.get("visual") as Node).get("recoil_count"))
			highest_speed = maxf(highest_speed, a.velocity.length())
			for b: CharacterBody2D in members:
				if a != b: smallest = minf(smallest, a.position.distance_to(b.position))
		check(recoil_total == shot_history.size(), "Each of the three shots has its own recoil")
		check(smallest >= 12.5 and highest_speed <= 34.1, "Formation preserves body spacing and slow movement")
		var attacker: CharacterBody2D = pack.get("_attacker") as CharacterBody2D
		if is_instance_valid(attacker):
			attacker.call("take_damage", 6.0)
			await frames(50)
			check((pack.get("members") as Array).size() == 4, "Killing the active member cancels its turn safely")
		var before: int = int(pack.get("shots_fired"))
		player.position += Vector2(600, 0)
		await frames(480)
		check(int(pack.get("shots_fired")) == before and int(pack.get("state")) == 0, "Leaving the anchor leash stops attacks and returns the pack home")
		var all_home: bool = true
		for member: Node2D in pack.get("members") as Array:
			if member.position.distance_to(member.get("home_position") as Vector2) > 7.0: all_home = false
		check(all_home, "Returning members recover their own home positions")
		report["pack"] = {"shots": shot_history.size(), "minimum_spacing": smallest, "navigation_build_usec": (pack.get("navigation") as EnemyNavigationGrid).build_usec}
		pack.call("dismiss")
		await frames(2)
		player.position = Vector2(800, 800)


func _orbs() -> void:
	player.health = 60.0
	player.contact_invulnerability = 0.0
	var friendly: CharacterBody2D = eye_at(player.position + Vector2(-45, 3))
	var shooter: CharacterBody2D = eye_at(player.position + Vector2(-100, 3))
	await frames(2)
	for index: int in range(3):
		var orb: Node2D = orb_at(shooter.position, Vector2.RIGHT, shooter)
		orb.call("_physics_process", 1.0)
		check(bool(orb.get("consumed")), "Fast orb resolves a swept player contact")
		player.contact_invulnerability = maxf(player.contact_invulnerability - 0.27, 0.0)
		await frames(1)
	check(is_equal_approx(player.health, 51.0), "Three low-damage spheres total nine damage")
	check(is_equal_approx(float(friendly.call("get_current_health")), 6.0) and AFFILIATION.are_allies(shooter, friendly), "Monster spheres recognize allies and pass through them")
	player.contact_invulnerability = 0.0
	player.dash_remaining = 0.2
	var dash_orb: Node2D = orb_at(shooter.position, Vector2.RIGHT, shooter)
	dash_orb.call("_physics_process", 1.0)
	check(is_equal_approx(player.health, 51.0), "Dashing player remains protected")
	dash_orb.call("dismiss")
	player.dash_remaining = 0.0
	var reflected: Node2D = orb_at(player.position + Vector2(-9, 3), Vector2.RIGHT, shooter)
	check(bool(reflected.call("parry", player)), "Orb supports the existing parry contract")
	reflected.call("_physics_process", 1.0)
	check(not bool(friendly.call("is_alive")) and is_equal_approx(player.health, 51.0), "Reflected orb changes faction and hits the first monster")
	friendly.call("dismiss")
	var wall: StaticBody2D = StaticBody2D.new()
	wall.position = player.position + Vector2(-40, 3)
	var collision: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(6, 60)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	await frames(2)
	var blocked: Node2D = orb_at(shooter.position, Vector2.RIGHT, shooter)
	blocked.call("_physics_process", 1.0)
	check(bool(blocked.get("consumed")) and is_equal_approx(player.health, 51.0), "Solid cover intercepts an orb before the player")
	var expired: Node2D = orb_at(shooter.position, Vector2.LEFT, shooter)
	expired.call("_physics_process", 3.5)
	check(bool(expired.get("consumed")), "Orbs expire within their bounded lifetime")
	wall.queue_free()
	shooter.call("dismiss")
	await frames(3)


func _integration() -> void:
	world.queue_free()
	await frames(3)
	var arena: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("flying_eye_spawns_enabled", true)
	arena.set("insect_spawns_enabled", false)
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	var zones: Node2D = arena.get_node("FlyingEyeZones") as Node2D
	(zones.get("_random") as RandomNumberGenerator).seed = 19
	await frames(180)
	var active: Array = zones.get("active_zones") as Array
	check((zones.get("zones") as Dictionary).size() == 20 and active.size() == 2, "LDtk loads twenty authored zones and keeps two active")
	check(int(zones.call("live_count")) > 0 and (zones.call("all_packs") as Array).size() <= 4 and int(zones.call("live_count")) <= 20, "Ambient packs spawn within the four-pack/twenty-eye ceiling")
	var logs: Array = zones.get("spawn_log") as Array
	var offscreen: bool = true
	for entry: Dictionary in logs:
		for point: Vector2 in entry.members as Array:
			var height: float = float(arena.get_node("TerrainElevation").call("height_at", point))
			if (entry.viewport as Rect2).grow(56.0).has_point(point - Vector2(0, height + 8.0)): offscreen = false
	check(offscreen and not logs.is_empty(), "Every recorded member spawns outside the visible camera with padding")
	var spacing: bool = true
	var packs: Array = zones.call("all_packs") as Array
	for a: Node2D in packs:
		for b: Node2D in packs:
			if a != b and (a.get("anchor") as Vector2).distance_to(b.get("anchor") as Vector2) < 320.0: spacing = false
	check(spacing, "Independent pack anchors remain at least 320 px apart")
	var quota_before: int = int(zones.get("spawn_total"))
	if not packs.is_empty():
		var cleared_pack: Node2D = packs[-1] as Node2D
		var cleared_id: int = cleared_pack.get_instance_id()
		for eye: Node2D in (cleared_pack.get("members") as Array).duplicate(): eye.call("take_damage", 6.0)
		await frames(100)
		var cleaned: bool = true
		for remaining: Node2D in zones.call("all_packs") as Array:
			if remaining.get_instance_id() == cleared_id: cleaned = false
		check(cleaned and int(zones.get("spawn_total")) == quota_before, "A defeated pack is cleaned up without refilling its zone quota")
	var first: StringName = zones.get("current_zone") as StringName
	var candidate: StringName = &""
	for id: StringName in zones.get("zones") as Dictionary:
		if not active.has(id):
			candidate = id
			break
	var third_center: Vector2 = ((zones.get("zones") as Dictionary)[candidate].rect as Rect2).get_center()
	player.position = third_center
	await frames(3)
	check((zones.get("active_zones") as Array).size() == 2 and (zones.get("active_zones") as Array).has(candidate) and int(zones.get("evictions")) == 1, "Entering a third zone evicts the oldest while keeping two")
	check((zones.get("active_zones") as Array).has(first), "The most recently visited zone is retained")
	var count_before: int = int(zones.get("spawn_total"))
	var encounter: Node2D = (arena.get_node("SpiritHordes").get("encounters") as Array)[0] as Node2D
	var source_packs: Array = zones.call("all_packs") as Array
	if not source_packs.is_empty():
		var source_pack: Node2D = source_packs[0] as Node2D
		var source_members: Array = source_pack.get("members") as Array
		zones.call("_on_shot_requested", source_members[0], Vector2.RIGHT, source_pack)
		check(zones.get_node("Projectiles").get_child_count() == 1, "Ambient factory produces a live orb before altar activation")
	player.position = encounter.get("arena_center") as Vector2
	player.snap_floor_height()
	encounter.call("begin")
	var no_attack: bool = true
	for pack: Node2D in zones.call("all_packs") as Array:
		if not bool(pack.get("suspended")): no_attack = false
	await frames(100)
	check(bool(zones.get("suspended")) and no_attack and int(zones.get("spawn_total")) == count_before, "Altar start synchronously cancels ambient turns and suspends new spawns")
	check(zones.get_node("Projectiles").get_child_count() == 0, "Altar event leaves no ambient orbs")
	encounter.call("_on_player_defeated")
	await frames(3)
	check(not bool(zones.get("suspended")) and (encounter.get("actors") as Array).is_empty(), "Real altar abort cleans up its spirits and resumes exploration")
	# Inspect an actual spawned pack on native terrain, with no test sprites.
	packs = zones.call("all_packs") as Array
	if not packs.is_empty():
		var selected: Node2D = packs[0] as Node2D
		player.position = selected.get("anchor") as Vector2
		player.snap_floor_height()
		var camera: Camera2D = player.get_node("Camera2D") as Camera2D
		camera.position_smoothing_enabled = false
		camera.zoom = Vector2.ONE * 1.8
		camera.force_update_scroll()
		await frames(150)
		if rendered:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://output/flying_eye/in_game.png")
	report["zones"] = {"active": (zones.get("active_zones") as Array).size(), "spawned_packs": int(zones.get("spawn_total")), "live_eyes": int(zones.call("live_count")), "evictions": int(zones.get("evictions"))}
	arena.queue_free()
	await frames(3)


func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	fixture_player()
	await frames(3)
	await _visual_and_health()
	await _packs()
	await _orbs()
	await _integration()
	report["checks"] = checks
	report["failures"] = failures
	var output: FileAccess = FileAccess.open("res://output/flying_eye/regression.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("FLYING_EYE_REGRESSION " + ("PASS " if failures.is_empty() else "FAIL ") + str(checks) + " checks")
	quit(0 if failures.is_empty() else 1)
