extends SceneTree

const HORDE: Script = preload("res://scripts/dungeon/spirit_horde_encounter.gd")
const BELL: Script = preload("res://scripts/enemies/bone_bell.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const FACTORY: Script = preload("res://scripts/combat/manifestations/manifestation_factory.gd")
const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const ORB: Script = preload("res://scripts/combat/projectiles/flying_eye_orb.gd")
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


func exercise_wave(bell: BELL, player: Player) -> void:
	player.contact_invulnerability = 1000.0
	var entry_position: Vector2 = bell.global_position
	for index: int in range(420):
		if bell.phase == BELL.Phase.WINDUP:
			break
		await tick()
	check(bell.phase == BELL.Phase.WINDUP and bell.global_position.distance_to(entry_position) > 45.0, "The bell floats into range before it attacks")
	check(bell._pulses.is_empty() and bell.art.frame == 4 and bell.is_in_group(&"sound_fields"), "The first pose starts a harmless warning and raises the field")
	var warning: AnimatedSprite2D = bell.get_node_or_null("ImpactWarning") as AnimatedSprite2D
	check(warning != null and warning.visible and warning.is_playing(), "The shared triangle warns during the windup")
	var center: Vector2 = bell.global_position
	var original_health: float = player.health
	var safe_direction: Vector2 = Vector2.from_angle(bell._attack_angle + BELL.GAP_CENTERS[0])
	var safe_point: Vector2 = center + safe_direction * 100.0
	place(player, safe_point - player.floor_visual_offset() + Vector2(0, 5))
	player.contact_invulnerability = 0.0
	var field_hit: Dictionary = CONTACTS.sound_field_hit(self, safe_point, center, 2.0)
	check(bool(field_hit.get("sound_block", false)) and is_equal_approx(center.distance_to(field_hit.position as Vector2), BELL.FIELD_RADIUS + 2.0), "The intact sound field catches shots even along a dodge gap")
	var gun: Node2D = player.get_node("BoosterShooter") as Node2D
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var effects: CombatEffects = gun.get("effects") as CombatEffects
	var shot: Node2D = FACTORY.projectile(CATALOG.MANIFESTATIONS[1], runtime.create_attack(),
		current_scene, center + safe_direction * 24.0, -safe_direction, effects, player, ProceduralWeaponSpriteFactory.new())
	var enemy_shot: ORB = ORB.new()
	enemy_shot.target = player
	enemy_shot.direction = safe_direction
	current_scene.add_child(enemy_shot)
	enemy_shot.global_position = center + safe_direction * 26.0 + Vector2(0, 8)
	for index: int in range(34):
		await tick()
	check(not is_instance_valid(shot) and bell.health == BELL.MAX_HEALTH, "A real projectile is absorbed during the warning")
	check(not is_instance_valid(enemy_shot) and player.health == original_health, "The field also absorbs enemy bullets from inside")
	check(bell._beats_played == 3 and bell._pulses.is_empty() and bell.art.frame >= 6, "All three warning beats precede the damaging pulses")
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/bone_bell/jogo-01-aviso.png")
	var largest_volley: int = 0
	for index: int in range(165):
		if bell.phase == BELL.Phase.RETREAT:
			break
		await tick()
		largest_volley = maxi(largest_volley, bell._pulses.size())
		if capture and bell._pulses.size() == 3 and absf(bell._phase_age - 0.72) < 0.009:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://output/bone_bell/jogo-02-tres-ondas.png")
	check(warning != null and not warning.visible, "The warning leaves when the waves start")
	check(bell.phase == BELL.Phase.RETREAT and largest_volley == 3 and bell._pulses.is_empty(), "The three pulses all travel out before the retreat")
	check(bell.global_position == center and player.health == original_health, "The bell holds still and all three gaps protect the player")
	check(not bell.is_in_group(&"sound_fields"), "The end of the volley drops the sound field")
	var cover: Node2D = Node2D.new()
	current_scene.add_child(cover)
	cover.global_position = safe_point - safe_direction * 55.0
	var original_members: Array[Node2D] = bell.horde_members
	bell.horde_members = [cover]
	var goal: Vector2 = bell._cover_position(bell._player_center())
	check(goal.distance_to(bell._player_center()) > cover.global_position.distance_to(bell._player_center()), "The retreat places an ally between the player and bell")
	for index: int in range(30):
		await tick()
	check(bell.phase == BELL.Phase.RETREAT and bell.global_position.distance_to(goal) < center.distance_to(goal), "The bell moves toward cover during cooldown")
	bell.horde_members = original_members
	cover.queue_free()
	for index: int in range(380):
		if bell.phase == BELL.Phase.RING:
			break
		await tick()
	check(bell.phase == BELL.Phase.RING, "The bell returns and attacks again after cooldown")
	var exposed_point: Vector2 = bell.global_position + Vector2.from_angle(bell._attack_angle) * 100.0
	place(player, exposed_point - player.floor_visual_offset() + Vector2(0, 5))
	# Player physics is paused in this fixture, so advance the regular hit immunity here.
	for index: int in range(140):
		if bell.phase == BELL.Phase.RETREAT:
			break
		player.contact_invulnerability = maxf(0.0, player.contact_invulnerability - 1.0 / 60.0)
		if bell._phase_age >= 0.94:
			player.dash_remaining = player.dash_duration
		bell.take_damage(1.0)
		await tick()
	player.dash_remaining = 0.0
	check(is_equal_approx(player.health, original_health - 2 * BELL.DAMAGE), "Two solid pulses each hit once, and dashing dodges the third")
	check(bell.health == BELL.MAX_HEALTH, "The bell rejects direct damage for the entire volley")


func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	capture = "--capture" in OS.get_cmdline_user_args()
	if capture:
		DirAccess.make_dir_recursive_absolute("res://output/bone_bell")
	for path: String in ["res://scenes/maps/open_world.tscn", "res://scenes/dungeon/ldtk_arena.tscn"]:
		var scene: Node2D = await scene_at(path)
		var player: Player = scene.get_node("Nox") as Player
		player.set_physics_process(false)
		player.card_effects.set_physics_process(false)
		var totems: Array = scene.get_node("HordePedestals").get("pedestals") as Array
		check(totems.size() == (6 if path.ends_with("open_world.tscn") else 1), "All authored altars are tested")
		for index: int in range(totems.size()):
			var totem: Node2D = totems[index] as Node2D
			var encounter: HORDE = totem.get("encounter") as HORDE
			place(player, totem.global_position + Vector2(20, 0))
			player.health = player.max_health
			player.contact_invulnerability = 1000.0
			encounter.profile.set("miniboss_kind", HORDE.PROFILE.MinibossKind.BONE_BELL)
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
			check(encounter.phase == HORDE.Phase.CLEARED and bell._pulses.is_empty() and encounter.miniboss == null, "Defeating the bell clears the altar and removes its waves")
			await tick()
		scene.queue_free()
		await tick()
	print("BONE_BELL ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
