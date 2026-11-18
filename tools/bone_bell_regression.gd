extends SceneTree

const HORDE: Script = preload("res://scripts/dungeon/spirit_horde_encounter.gd")
const BELL: Script = preload("res://scripts/enemies/bone_bell.gd")
const PROFILE: Script = preload("res://scripts/enemies/spirit_horde_profile.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
var failures: Array[String] = []
var checks: int = 0
var capture: bool = false


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func tick() -> void:
	await physics_frame
	await process_frame


func scene_at(path: String) -> Node2D:
	var scene: Node2D = (load(path) as PackedScene).instantiate() as Node2D
	scene.set("warp_entry_cutscene_enabled", false)
	scene.set("insect_spawns_enabled", false)
	root.add_child(scene)
	current_scene = scene
	while not bool(scene.get("entry_complete")):
		await process_frame
	for name: String in ["FlyingSkullZones", "SlimeZones"]:
		var zone: Node = scene.get_node_or_null(name)
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


func wait_for_wave(bell: BELL) -> void:
	for index: int in range(420):
		if bell._wave_live:
			break
		await tick()


func exercise_wave(bell: BELL, player: Player) -> void:
	player.contact_invulnerability = 1000.0
	var entry_position: Vector2 = bell.global_position
	for index: int in range(420):
		if bell.phase == BELL.Phase.WINDUP:
			break
		await tick()
	check(bell.phase == BELL.Phase.WINDUP and bell.global_position.distance_to(entry_position) > 45.0, "The bell floats into range before it attacks")
	check(not bell._wave_live and bell.art.frame >= 4 and bell.art.frame < 8, "Four preparation poses precede the wave")
	await wait_for_wave(bell)
	check(bell._wave_live and bell.art.frame == 8, "The wave starts on the first strike sprite")
	player.contact_invulnerability = 0.0
	var original_health: float = player.health
	var hover_point: Vector2 = bell._wave_origin + Vector2.from_angle(bell._gap_angle) * 100.0
	place(player, hover_point - player.floor_visual_offset() + Vector2(0, 5))
	for index: int in range(72):
		await tick()
	check(player.health == original_health, "The wave's open sector is safe")
	await wait_for_wave(bell)
	check(bell._wave_live, "The bell recovers and rings again")
	var exposed_point: Vector2 = bell._wave_origin + Vector2.from_angle(bell._gap_angle + PI) * 100.0
	place(player, exposed_point - player.floor_visual_offset() + Vector2(0, 5))
	for index: int in range(72):
		await tick()
		if capture and bell._wave_radius > 104.0 and bell._wave_radius <= 107.0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://output/bone_bell/jogo-onda.png")
	check(is_equal_approx(player.health, original_health - BELL.DAMAGE), "The solid arc deals one six-damage hit")
	await wait_for_wave(bell)
	check(bell._wave_live, "The next wave starts")
	exposed_point = bell._wave_origin + Vector2.from_angle(bell._gap_angle + PI) * 100.0
	place(player, exposed_point - player.floor_visual_offset() + Vector2(0, 5))
	player.contact_invulnerability = 0.0
	player.dash_remaining = player.dash_duration
	for index: int in range(72):
		await tick()
	player.dash_remaining = 0.0
	check(is_equal_approx(player.health, original_health - BELL.DAMAGE), "A dash crosses the solid wave unharmed")


func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	capture = "--capture" in OS.get_cmdline_user_args()
	for path: String in ["res://scenes/maps/open_world.tscn", "res://scenes/dungeon/ldtk_arena.tscn"]:
		var scene: Node2D = await scene_at(path)
		var player: Player = scene.get_node("Nox") as Player
		player.set_physics_process(false)
		var totems: Array = scene.get_node("HordePedestals").get("pedestals") as Array
		check(totems.size() == (6 if path.ends_with("open_world.tscn") else 1), "All authored altars are tested")
		for index: int in range(totems.size()):
			var totem: Node2D = totems[index] as Node2D
			var encounter: HORDE = totem.get("encounter") as HORDE
			place(player, totem.global_position + Vector2(20, 0))
			player.health = player.max_health
			player.contact_invulnerability = 1000.0
			encounter.profile.miniboss_kind = PROFILE.MinibossKind.BONE_BELL
			encounter.begin()
			for frame: int in range(1200):
				if is_instance_valid(encounter.miniboss):
					break
				await tick()
			var bell: BELL = encounter.miniboss as BELL
			check(is_instance_valid(bell) and get_nodes_in_group(&"flying_centipedes").is_empty(), encounter.encounter_id + " spawns the bell instead of the centipede")
			if not is_instance_valid(bell):
				encounter.skip_to_completion()
				continue
			check(bell.health == 30.0 and bell.is_in_group(&"enemy_bodies") and bell.get_meta(&"is_boss") == true, "The bell uses the combat target contract with 30 HP")
			encounter.set_physics_process(false)
			if index == 0 and totems.size() == 6:
				# Keep the existing wave present but isolate the bell's damage during the move test.
				for shot: Node2D in encounter.projectiles.duplicate():
					shot.call("dismiss")
				await exercise_wave(bell, player)
				var at: Vector2 = CONTACTS.damage_center(bell)
				var space: PhysicsDirectSpaceState2D = bell.get_world_2d().direct_space_state
				var hit: Dictionary = CONTACTS.sweep(self, space, at - Vector2(12, 0), at, 4, 1.0)
				check(hit.get("collider") == bell, "The bell is hittable in its projected flying position")
			encounter.defeated_count = encounter.kill_target
			check(not encounter._check_completion() and encounter.phase == HORDE.Phase.ACTIVE, "Horde criteria keep the altar locked while the bell is alive")
			var effects: CombatEffects = player.get_node("BoosterShooter").get("effects") as CombatEffects
			effects.apply_hit(bell, 3.0, Vector2.RIGHT, 18.0)
			check(bell.health == 27.0, "Player damage reduces the bell's health")
			effects.apply_hit(bell, 27.0, Vector2.RIGHT, 18.0)
			check(encounter.phase == HORDE.Phase.CLEARED and not bell._wave_live and encounter.miniboss == null, "Defeating the bell clears the altar and removes its wave")
			await tick()
		scene.queue_free()
		await tick()
	print("BONE_BELL ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
