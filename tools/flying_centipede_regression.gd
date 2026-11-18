extends SceneTree

const BOSS: Script = preload("res://scripts/enemies/flying_centipede.gd")
const HORDE: Script = preload("res://scripts/dungeon/spirit_horde_encounter.gd")
const FACTORY: Script = preload("res://scripts/combat/manifestations/manifestation_factory.gd")
const MODEL: ProceduralManifestationModel = preload("res://resources/weapons/procedural/M01.tres")
var failures: Array[String] = []
var checks: int = 0
var kill_procs: int = 0
var capture: bool = false
var activation_ms: Array[float] = []
var opening_seconds: Array[float] = []
var entry_delays: Array[float] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _record_kill() -> void:
	kill_procs += 1


func ticks(frames: int) -> void:
	for index: int in range(frames):
		await physics_frame
	await process_frame


func capture_frame(stem: String) -> void:
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/centopeia_voadora/" + stem + ".png")


func play(scene_path: String) -> Node2D:
	var scene: Node2D = (load(scene_path) as PackedScene).instantiate() as Node2D
	scene.set("warp_entry_cutscene_enabled", false)
	scene.set("insect_spawns_enabled", false)
	root.add_child(scene)
	current_scene = scene
	while not bool(scene.get("entry_complete")):
		await process_frame
	for path: String in ["FlyingSkullZones", "SlimeZones"]:
		var zone: Node = scene.get_node_or_null(path)
		if zone != null:
			zone.set_physics_process(false)
	return scene


func place(player: Player, point: Vector2) -> void:
	player.global_position = point
	player.snap_floor_height()
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()


func _fire_at_segment(boss: BOSS, player: Player, scene: Node2D, effects: CombatEffects) -> void:
	var target: Node2D = boss.segments[3]
	var direction: Vector2 = Vector2.UP.rotated(target.global_rotation).orthogonal()
	var attack: CardAttack = CardAttack.new()
	attack.damage = 3.0
	attack.projectile_speed = MODEL.card.projectile_speed
	attack.projectile_lifetime = MODEL.card.projectile_lifetime
	attack.on_weapon_kill = _record_kill
	var shot: Node2D = FACTORY.projectile(MODEL, attack, scene, target.global_position - direction * 17.0,
		direction, effects, player, ProceduralWeaponSpriteFactory.new())
	var neighbor: Node2D = boss.segments[4]
	await ticks(6)
	check(not boss.segments.has(target) and boss.segments.size() == 7, "A real projectile breaks the segment it hits")
	check(float(neighbor.call("get_current_health")) == 3.0 and kill_procs == 0, "A broken piece leaves its neighbor intact and is not a weapon kill")
	if is_instance_valid(shot):
		shot.queue_free()


func _destroy_remaining(boss: BOSS, effects: CombatEffects) -> void:
	for segment: Node2D in boss.segments.duplicate():
		effects.apply_hit(segment, 3.0, Vector2.RIGHT, 0.0, _record_kill)


func _wait_opening(encounter: HORDE) -> void:
	var start: int = Time.get_ticks_usec()
	encounter.begin()
	activation_ms.append((Time.get_ticks_usec() - start) / 1000.0)
	check(encounter.actors.is_empty() and encounter.miniboss == null, "Activation schedules creatures without instantiating them")
	await ticks(25)
	check(encounter.actors.is_empty() and encounter.miniboss == null, "Nothing spawns before the opening delay")
	var before: int = 0
	var largest_batch: int = 0
	var waiting_frames: int = 25
	for frame: int in range(1200):
		await ticks(1)
		waiting_frames += 1
		largest_batch = maxi(largest_batch, encounter.actors.size() - before)
		before = encounter.actors.size()
		if before > 0 and opening_seconds.size() < activation_ms.size():
			opening_seconds.append(waiting_frames / 60.0)
		if encounter._opening_remaining == 0 and is_instance_valid(encounter.miniboss):
			break
	var elapsed_since_first: float = encounter.elapsed_seconds - encounter._first_mob_at
	entry_delays.append(elapsed_since_first)
	check(encounter._first_mob_at >= 0.0 and before > 0 and largest_batch <= 2, "The regular wave starts in batches before the boss")
	check(elapsed_since_first >= float(encounter.profile.get("miniboss_entry_delay")) and elapsed_since_first <= 8.1, "The boss waits for cover after the first regular spawns")


func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	var world: Node2D = await play("res://scenes/maps/open_world.tscn")
	var player: Player = world.get_node("Nox") as Player
	player.set_physics_process(false)
	player.contact_invulnerability = 0.0
	var effects: CombatEffects = player.get_node("BoosterShooter").get("effects") as CombatEffects
	var totems: Array = world.get_node("HordePedestals").get("pedestals") as Array
	check(totems.size() == 6, "Six authored world altars are covered")
	for index: int in range(totems.size()):
		var totem: Node2D = totems[index] as Node2D
		var encounter: HORDE = totem.get("encounter") as HORDE
		place(player, totem.global_position + Vector2(20.0, 0.0))
		player.heal_full()
		player.contact_invulnerability = 1000.0
		if index == 0:
			# Let the real proximity warmup run before activating the first altar.
			for frame: int in range(1200):
				if not encounter.needs_navigation_warmup():
					break
				await ticks(1)
			check(not encounter.needs_navigation_warmup(), "Nearby exploration prepares the altar's ground grid")
		await _wait_opening(encounter)
		if index == 0:
			check(not opening_seconds.is_empty() and opening_seconds[0] <= 1.4, "A prepared arena starts its opening wave on the initial delay")
		var boss: BOSS = encounter.miniboss as BOSS
		check(is_instance_valid(boss) and boss.segments.size() == 8, encounter.encounter_id + " spawns the boss with eight pieces")
		if not is_instance_valid(boss):
			encounter.skip_to_completion()
			continue
		for segment: Node2D in boss.segments:
			check(float(segment.call("get_current_health")) == 3.0, "Each piece starts with three HP")
		encounter.set_physics_process(false)
		kill_procs = 0
		if index == 0:
			var screen_position: Vector2 = boss.to_local(encounter.actors[0].global_position)
			var squad: Array[Node2D] = boss.horde_members
			boss.horde_members = [encounter.actors[0]]
			var right_cover: float = boss._radius_behind_horde(screen_position - Vector2(125, 0), Vector2.RIGHT)
			var left_cover: float = boss._radius_behind_horde(screen_position - Vector2(125, 0), Vector2.LEFT)
			check(right_cover > BOSS.ORBIT_RADIUS and left_cover == BOSS.ORBIT_RADIUS, "The orbit expands only toward mobs that can screen the boss")
			boss.horde_members = squad
			player.contact_invulnerability = 0.0
			var slowest_step: float = INF
			for frame: int in range(1050):
				if boss.flight == BOSS.Flight.DIVE:
					break
				var last: Vector2 = boss.head.position
				await ticks(1)
				slowest_step = minf(slowest_step, last.distance_to(boss.head.position))
			check(boss.flight == BOSS.Flight.DIVE and boss._orbit_turn >= TAU and player.health == player.max_health, "The boss circles before its first dive without dealing contact damage")
			await capture_frame("jogo-03-circulo")
			var captured_charge: bool = false
			for frame: int in range(180):
				if boss.flight == BOSS.Flight.RETREAT:
					break
				if player.health < player.max_health and capture and not captured_charge:
					await capture_frame("jogo-04-investida")
					captured_charge = true
				var last: Vector2 = boss.head.position
				await ticks(1)
				slowest_step = minf(slowest_step, last.distance_to(boss.head.position))
			check(slowest_step > 1.0, "The head stays in motion during the circle, dive and charge")
			check(player.health == player.max_health - 6.0, "The charge passes through Nox and hurts once")
			check(boss.flight == BOSS.Flight.RETREAT, "The boss continues past Nox and retreats")
			for frame: int in range(1000):
				await ticks(1)
				if boss.flight == BOSS.Flight.DIVE:
					break
			check(boss.flight == BOSS.Flight.DIVE and boss._orbit_turn >= TAU, "The boss retreats and circles before the next pass")
		boss.set_physics_process(false)
		if index == 0:
			var middle: Node2D = boss.segments[3]
			middle.call("take_damage", 1.0)
			check(boss.segments.size() == 8 and float(middle.call("get_current_health")) == 2.0, "Partial hits only reduce the struck piece's HP")
			await _fire_at_segment(boss, player, world, effects)
			check(encounter.defeated_count == 0, "A broken piece does not count toward the horde target")
		if index == 2:
			_destroy_remaining(boss, effects)
			check(encounter.phase == HORDE.Phase.ACTIVE and kill_procs == 1, "An early boss defeat leaves the normal horde objective active")
		if index % 2 == 0:
			encounter._elapsed = 40.0
			encounter._check_completion()
		else:
			encounter.defeated_count = encounter.kill_target - 1
			encounter.actors.front().call("take_damage", 3.0)
		if index != 2:
			check(encounter.phase == HORDE.Phase.ACTIVE and bool(encounter.arena_boundary.get("active")), "Objective reached before boss keeps the arena active")
			check(not bool(totem.get_node("BoosterOpener").get("interaction_enabled")), "The reward stays locked while the boss lives")
			var live_before: int = encounter.actors.size()
			encounter._spawn_remaining = 0.0
			encounter._physics_process(0.0)
			check(encounter.actors.size() == live_before, "Reinforcements stop after the horde objective")
			_destroy_remaining(boss, effects)
		check(encounter.phase == HORDE.Phase.CLEARED and encounter.miniboss == null and kill_procs == 1, "Both objectives clear the altar and credit only one boss kill")
		check(encounter.completion_reason == (&"time" if index % 2 == 0 else &"kills"), "Clear preserves the first horde criterion")
		check(bool(totem.get_node("BoosterOpener").get("interaction_enabled")), "Victory unlocks the totem reward")
		await ticks(14)
	world.queue_free()
	await ticks(2)
	var tutorial: Node2D = await play("res://scenes/dungeon/ldtk_arena.tscn")
	player = tutorial.get_node("Nox") as Player
	var tutorial_totem: Node2D = tutorial.get_node("HordePedestals").get("pedestals")[0] as Node2D
	var tutorial_encounter: HORDE = tutorial_totem.get("encounter") as HORDE
	place(player, tutorial_totem.global_position)
	player.contact_invulnerability = 1000.0
	await _wait_opening(tutorial_encounter)
	check(is_instance_valid(tutorial_encounter.miniboss) and (tutorial_encounter.miniboss as BOSS).segments.size() == 8, "The tutorial altar also spawns the miniboss")
	tutorial_encounter._on_player_defeated()
	check(tutorial_encounter.phase == HORDE.Phase.ABORTED and tutorial_encounter.miniboss == null, "Defeat cleans up the boss without clearing the altar")
	await ticks(14)
	check(get_nodes_in_group(&"flying_centipedes").is_empty(), "No boss remains after abort")
	tutorial.queue_free()
	await ticks(2)
	print("FLYING_CENTIPEDE ", JSON.stringify({"checks": checks, "failures": failures,
		"activation_ms": activation_ms, "opening_seconds": opening_seconds, "entry_delays": entry_delays}))
	quit(0 if failures.is_empty() else 1)
