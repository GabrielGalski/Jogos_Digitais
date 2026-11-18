extends SceneTree
## Real physics/animation, melee timing, fly replacement, individual retreats and map streaming.
const PACK: Script = preload("res://scripts/enemies/insects/insect_pack.gd")
const ZONES: Script = preload("res://scripts/dungeon/insect_zones.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const PARRY: Script = preload("res://scripts/combat/player_parry.gd")
const REMAINS: Script = preload("res://scripts/visual/enemy_remains.gd")
const PALETTES: Script = preload("res://scripts/visual/insect_palettes.gd")
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
		push_error("[INSECTS] " + message)


func frames(count: int) -> void:
	for index: int in range(count): await physics_frame


func pack_at(kinds: Array[StringName], starts: Array[Vector2]) -> Node2D:
	var pack: Node2D = PACK.new() as Node2D
	world.add_child(pack)
	pack.call("configure", starts[0], starts, kinds, player,
		func(_point: Vector2) -> bool: return true, Callable(), 280.0, 192.0, 0.0)
	var neighbors: Array[Node2D] = []
	for actor: Node2D in pack.get("members") as Array: neighbors.append(actor)
	pack.set("neighbors", neighbors)
	return pack


func _assets() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemies/insects/sprite_map.json")) as Dictionary
	var total: int = 0
	for kind: String in manifest.models:
		var resource: SpriteFrames = load("res://resources/enemies/insects/%s_frames.tres" % kind) as SpriteFrames
		for clip: String in manifest.models[kind]:
			var info: Dictionary = manifest.models[kind][clip] as Dictionary
			check(FileAccess.get_sha256(str(info.source)) == str(info.source_sha256), "%s %s source sheet preserved" % [kind, clip])
			check(resource.get_frame_count(clip) == int(info.frames), "%s %s complete animation" % [kind, clip])
			for index: int in range(int(info.frames)):
				if resource.get_frame_texture(clip, index).get_size() != Vector2(48, 48): check(false, "Fixed 48x48 frame canvas")
				total += 1
	check(total == 82, "All 82 poses exported with a common pivot")
	var zones: Node2D = ZONES.new() as Node2D
	var counts: Dictionary[StringName, int] = {&"tall": 0, &"fly": 0, &"little": 0}
	(zones.get("_random") as RandomNumberGenerator).seed = 37
	var valid: bool = true
	var variants: Dictionary = {}
	var tall_packs: int = 0
	for index: int in range(1000):
		var count: int = 3 + index % 4
		var kinds: Array = zones.call("choose_composition", count) as Array
		if kinds.size() != count or kinds.count(&"tall") > 1: valid = false
		variants[str(kinds)] = true
		if kinds.has(&"tall"): tall_packs += 1
		for kind: StringName in kinds: counts[kind] += 1
	check(valid and variants.size() > 12, "Varied 3-6 enemy compositions with at most one tall")
	check(counts[&"little"] > counts[&"fly"] and counts[&"fly"] > counts[&"tall"], "Spawn frequency is little > fly > tall")
	check(tall_packs >= 450 and tall_packs <= 600, "Tall appears in about half of the mixed packs")
	report["composition_sample"] = counts
	report["tall_pack_fraction"] = tall_packs / 1000.0
	zones.free()


func _combat_contract() -> void:
	for kind: StringName in [&"tall", &"fly", &"little"]:
		var pack: Node2D = pack_at([kind], [player.position + Vector2(-16, 0)])
		pack.set_physics_process(false)
		var actor: InsectActor = (pack.get("members") as Array)[0] as InsectActor
		actor.set_physics_process(false)
		actor.engaged = true
		actor.set("_cooldown", 0.0)
		player.health = 60.0
		player.contact_invulnerability = 0.0
		actor.begin_attack()
		actor.call("_update_attack", actor.profile.windup * 0.5)
		check(is_equal_approx(player.health, 60.0), "%s telegraph deals no early contact damage" % kind)
		actor.call("_update_attack", actor.profile.windup * 0.5 + 0.001)
		check(is_equal_approx(player.health, 60.0 - actor.profile.damage), "%s impact deals its configured damage" % kind)
		actor.call("_update_attack", 1.0)
		check(actor.hits_landed == 1, "%s attack damages only once" % kind)
		var capsule: Dictionary = actor.get_projectile_hurt_capsule()
		var hit: Dictionary = CONTACTS.sweep(self, world.get_world_2d().direct_space_state,
			actor.position + Vector2(-35, -8), actor.position + Vector2(35, -8), 4, 2.0)
		check(hit.get("collider") == actor and is_equal_approx(float(capsule.height), 18.0 * actor.profile.visual_scale), "%s exposes its scaled body to swept projectiles" % kind)
		var health_before: float = actor.health
		actor.take_damage(3.0)
		check(is_equal_approx(actor.health, health_before - 3.0), "%s receives real base-three damage" % kind)
		pack.call("dismiss")
		await frames(2)
	var defense_pack: Node2D = pack_at([&"tall"], [player.position + Vector2(-16, 0)])
	defense_pack.set_physics_process(false)
	var tall: InsectActor = (defense_pack.get("members") as Array)[0] as InsectActor
	tall.set_physics_process(false)
	tall.set("_cooldown", 0.0)
	player.health = 60.0
	player.contact_invulnerability = 0.0
	player.dash_remaining = 0.20
	tall.begin_attack()
	tall.call("_update_attack", tall.profile.windup + 0.01)
	check(is_equal_approx(player.health, 60.0), "Dash evades an active insect strike")
	player.dash_remaining = 0.0
	tall.cancel_attack()
	tall.begin_attack()
	check(player.try_parry(), "Player can begin the existing parry")
	tall.call("_update_attack", tall.profile.windup + 0.01)
	check(not tall.is_alive() and is_equal_approx(player.health, 60.0), "Insect melee uses the real parry and reflected damage")
	defense_pack.call("dismiss")
	await frames(4)
	player.parry.call("cancel")


func _tall() -> void:
	player.health = 60.0
	player.contact_invulnerability = 1000.0
	var pack: Node2D = pack_at([&"tall"], [player.position + Vector2(80, 0)])
	var tall: InsectActor = (pack.get("members") as Array)[0] as InsectActor
	var origin: Vector2 = tall.global_position
	await frames(60)
	var approach_travel: float = origin.distance_to(tall.global_position)
	check(approach_travel > 30.0 and approach_travel < 35.0, "Tall advances at the increased 33.6px/s speed")
	var silhouette: Rect2i = tall.visual.sprite_frames.get_frame_texture(&"idle", 0).get_image().get_used_rect()
	check(is_equal_approx(tall.visual.scale.y * silhouette.size.y, 25.2) and is_equal_approx(tall.profile.body_radius, 7.2), "Tall's original 21px silhouette is 25.2px tall with matching collision scale")
	report["tall_measurements"] = {"source_height": silhouette.size.y, "world_height": silhouette.size.y * tall.visual.scale.y, "speed": tall.profile.movement_speed, "travel_first_second": approach_travel}
	await frames(150)
	check(tall.attacks_started > 0 and tall.player_distance() < 30.0, "Tall advances from range and commits its slow strike")
	for index: int in range(140):
		if tall.attack_in_progress(): break
		await frames(1)
	var age: float = float(tall.get("_attack_age"))
	tall.take_damage(3.0)
	tall.receive_impact(Vector2.RIGHT, 100.0)
	check(tall.attack_in_progress() and is_equal_approx(float(tall.get("_attack_age")), age), "Tall absorbs damage without cancelling its attack")
	check(is_equal_approx(tall.health, 27.0) and tall.hit_velocity.length() <= 16.0, "Tall has high health and resists displacement")
	await frames(220)
	check(tall.attacks_started >= 3, "Tall continuously repeats attacks without retreating")
	pack.call("dismiss")
	await frames(3)


func _little_steering() -> void:
	player.health = 60.0
	player.contact_invulnerability = 1000.0
	var pack: Node2D = pack_at([&"little", &"tall"], [player.position + Vector2(170, 0), player.position + Vector2(210, -35)])
	var little: InsectActor = (pack.get("members") as Array)[0] as InsectActor
	var cover: InsectActor = (pack.get("members") as Array)[1] as InsectActor
	cover.set_physics_process(false)
	var smallest_weave: float = 1.0
	var largest_weave: float = -1.0
	var longest_stop: int = 0
	var stopped: int = 0
	var circle_frames: int = 0
	var zero_orders: int = 0
	var previous: Vector2 = little.global_position
	var previous_heading: float = 0.0
	var turns: Array[float] = []
	for index: int in range(480):
		if index == 240: little.take_damage(3.0)
		await frames(1)
		var movement: Vector2 = little.global_position - previous
		if index > 5 and movement.length() < 0.04:
			stopped += 1
			longest_stop = maxi(longest_stop, stopped)
		else: stopped = 0
		if little.desired_velocity.length() < 1.0: zero_orders += 1
		if int(little.brain.get("state")) == 2: circle_frames += 1
		if index > 5 and index < 125:
			var toward: Vector2 = little.global_position.direction_to(player.global_position)
			var weave: float = toward.cross(little.desired_velocity.normalized())
			smallest_weave = minf(smallest_weave, weave)
			largest_weave = maxf(largest_weave, weave)
		if index > 5 and movement.length() > 0.04:
			turns.append(absf(angle_difference(previous_heading, movement.angle())))
			previous_heading = movement.angle()
		previous = little.global_position
	turns.sort()
	check(smallest_weave < -0.12 and largest_weave > 0.12, "Little weaves to both sides of its pursuit path")
	check(circle_frames > 15 and zero_orders <= 6, "Little circles behind cover instead of receiving idle orders")
	check(longest_stop <= 6, "Little remains physically moving through retreat, hit reaction and re-approach")
	check(little.attacks_started >= 2, "Continuous movement still permits repeated independent attacks")
	check(turns[int(turns.size() * 0.95)] < 0.14, "Little turns in small smooth curves at physics rate")
	report["little_steering"] = {"weave_min": smallest_weave, "weave_max": largest_weave, "circle_frames": circle_frames, "idle_orders": zero_orders, "longest_still_frames": longest_stop, "attacks": little.attacks_started, "turn_p95_radians": turns[int(turns.size() * 0.95)]}
	pack.call("dismiss")
	await frames(3)


func _death_remains() -> void:
	var manager: Node2D = REMAINS.new() as Node2D
	world.add_child(manager)
	manager.call("configure", func(_point: Vector2) -> bool: return true, player)
	manager.call("set_sprite_palette", PALETTES.remains_texture.bind(0))
	var pack: Node2D = pack_at([&"tall", &"fly", &"little"], [player.position + Vector2(-80, 0), player.position + Vector2(-45, 0), player.position + Vector2(0, -70)])
	pack.set_physics_process(false)
	var dead: Array[InsectActor] = (pack.get("members") as Array[InsectActor]).duplicate()
	for actor: InsectActor in dead:
		actor.remains_system = manager
		actor.visual.flip_h = true
		actor.take_damage(999.0)
	check(int(manager.call("total_count")) == 0, "Death animation plays before depositing its final frame")
	await frames(40)
	var corpses: Array[RefCounted] = []
	for chunk: Node2D in (manager.get("_chunks") as Dictionary).values(): corpses.append_array(chunk.get("pieces") as Array)
	check(corpses.size() == 3 and get_nodes_in_group(&"insects").is_empty(), "All three deaths leave a static frame after their combat actors are removed")
	for corpse: RefCounted in corpses:
		var kind: StringName = StringName(corpse.get("sprite_kind"))
		var source: Texture2D = corpse.get("source_texture") as Texture2D
		check(source.resource_path.ends_with("%s/death/death_06.png" % kind), "%s remains use exactly the authored final death frame" % kind)
		var body_scale: Vector2 = corpse.get("render_scale") as Vector2
		check(body_scale.x < 0.0 and is_equal_approx(body_scale.y, 1.2 if kind == &"tall" else 1.0), "%s corpse keeps facing, scale and foot pivot" % kind)
		var original: Image = source.get_image()
		var tinted: Image = ((manager.get("_textures") as Array)[int(corpse.get("texture_index"))] as Texture2D).get_image()
		if original.is_compressed(): original.decompress()
		var same_alpha: bool = true
		var recolored: bool = false
		for y: int in range(original.get_height()):
			for x: int in range(original.get_width()):
				if not is_equal_approx(original.get_pixel(x, y).a, tinted.get_pixel(x, y).a): same_alpha = false
				if not original.get_pixel(x, y).is_equal_approx(tinted.get_pixel(x, y)): recolored = true
		check(same_alpha and recolored, "%s remains preserve the source alpha while using the runtime palette" % kind)
	pack.queue_free()
	await frames(3)
	check(int(manager.call("total_count")) == 3, "Pack cleanup does not remove scene-owned corpses")
	manager.call("set_sprite_palette", PALETTES.remains_texture.bind(1))
	check(int(manager.call("total_count")) == 3, "Palette previews preserve existing remains")
	await frames(10) # Keep the same 0.30s post-death kick grace period as ghost debris.
	if not corpses.is_empty():
		var corpse: RefCounted = corpses[0]
		var origin: Vector2 = corpse.get("ground") as Vector2
		manager.set("_previous_feet", origin - Vector2(3, 0))
		check(bool(manager.call("_kick_if_near", corpse, origin + Vector2(3, 0), Vector2.RIGHT, 100.0)), "The existing ghost foot-kick logic also affects insect corpses")
		var chunk_key: Vector2i = Vector2i((origin / 128.0).floor())
		manager.call("_wake", corpse, (manager.get("_chunks") as Dictionary)[chunk_key])
		await frames(30)
		check((corpse.get("ground") as Vector2).distance_to(origin) > 2.0, "Kicked corpse moves cosmetically without a physics body")
		var expiry: float = float(corpse.get("expires_at"))
		manager.set("_elapsed", expiry + 0.17)
		manager.call("_physics_process", 0.005)
		check(float(corpse.get("opacity")) > 0.4 and float(corpse.get("opacity")) < 0.6, "Insect remains fade on the same fifteen-second schedule as ghosts")
		manager.set("_elapsed", expiry + 0.36)
		manager.call("_physics_process", 0.005)
		check(int(manager.call("total_count")) == 0, "Expired corpse textures leave no active pieces or floor chunks")
	manager.call("emit_spirit", player.position + Vector2(0, -8), player.position, Vector2.ZERO)
	var ghost_textures_only: bool = true
	for scrap: RefCounted in manager.get("active") as Array:
		if int(scrap.get("texture_index")) >= 4: ghost_textures_only = false
	check(ghost_textures_only, "Ghost deaths never sample insect corpse textures from the shared renderer")
	manager.queue_free()
	await frames(3)


func _navigation_safety() -> void:
	var gap: Rect2 = Rect2(player.position + Vector2(64, -36), Vector2(24, 72))
	var pack: Node2D = pack_at([&"little"], [player.position + Vector2(150, 0)])
	pack.set("floor_query", func(point: Vector2) -> bool: return not gap.has_point(point))
	var little: InsectActor = (pack.get("members") as Array)[0] as InsectActor
	var crossed_gap: bool = false
	var detour: float = 0.0
	for index: int in range(300):
		await frames(1)
		if gap.has_point(little.global_position): crossed_gap = true
		detour = maxf(detour, absf(little.global_position.y - player.position.y))
	check(not crossed_gap and detour > 36.0, "Curved steering takes the A* detour around an uncollided river gap")
	check(little.attacks_started > 0 and (pack.get("navigation") as EnemyNavigationGrid).path_queries >= 2, "Little completes its detour and reaches attack range")
	report["navigation_detour"] = {"maximum_lateral_distance": detour, "crossed_void": crossed_gap, "path_queries": (pack.get("navigation") as EnemyNavigationGrid).path_queries}
	pack.call("dismiss")
	await frames(3)


func _flies() -> void:
	var pack: Node2D = pack_at([&"fly", &"fly", &"little"], [player.position + Vector2(72, -20), player.position + Vector2(76, 22), player.position + Vector2(110, 0)])
	await frames(3)
	var first: InsectActor = pack.get("fly_attacker") as InsectActor
	check(first != null, "A fly receives the attacker position")
	if first != null:
		var distance_before: float = first.player_distance()
		first.take_damage(3.0)
		var replacement: InsectActor = pack.get("fly_attacker") as InsectActor
		check(replacement != null and replacement != first, "Taking damage immediately hands the attacker position to another fly")
		check(int(first.brain.get("state")) == 1 and not first.attack_in_progress(), "Damaged fly cancels its strike and retreats")
		await frames(30)
		check(first.player_distance() > distance_before + 15.0, "Damaged fly physically withdraws from the player")
		if is_instance_valid(replacement): replacement.take_damage(6.0)
		await frames(100)
		check(pack.get("fly_attacker") == first and first.is_alive(), "Surviving fly returns to the attack after recovering")
		check((pack.get("members") as Array).size() == 2, "Dead attacker is removed safely from the pack")
	var attacks: int = 0
	for actor: InsectActor in pack.get("members") as Array:
		if actor.profile.kind == &"fly" and actor.attack_in_progress(): attacks += 1
	check(attacks <= 1, "Fly attacks remain exclusive while littles act independently")
	pack.call("dismiss")
	await frames(3)


func _littles() -> void:
	player.health = 60.0
	player.contact_invulnerability = 0.0
	var pack: Node2D = pack_at([&"little", &"little", &"tall"], [player.position + Vector2(18, -8), player.position + Vector2(-20, 10), player.position + Vector2(92, 0)])
	var little: InsectActor = (pack.get("members") as Array)[0] as InsectActor
	var other: InsectActor = (pack.get("members") as Array)[1] as InsectActor
	var tall: InsectActor = (pack.get("members") as Array)[2] as InsectActor
	tall.set_physics_process(false)
	for index: int in range(120):
		if little.attacks_started > 0 and not little.attack_in_progress(): break
		await frames(1)
	check(little.attacks_started > 0 and other.attacks_started > 0, "Several littles attack independently, without a shared turn")
	check(int(little.brain.get("state")) == 1 and little.brain.get("cover") == tall, "Little selects a position behind a nearby enemy after striking")
	var after_strike: float = little.player_distance()
	await frames(36)
	check(little.player_distance() > after_strike + 12.0, "Little physically retreats after its quick attack")
	player.contact_invulnerability = 1000.0
	await frames(260)
	check(little.attacks_started >= 2, "Little returns on its own to attempt another strike")
	pack.call("dismiss")
	await frames(3)


func _integration() -> void:
	world.queue_free()
	await frames(3)
	var arena: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.contact_invulnerability = 1000.0
	var zones: Node2D = arena.get_node("InsectZones") as Node2D
	(zones.get("_random") as RandomNumberGenerator).seed = 19
	await frames(160)
	check(not bool(arena.get("flying_eye_spawns_enabled")) and get_nodes_in_group(&"flying_eyes").is_empty(), "Open world disables only Flying Eye spawning")
	check(not arena.get_node("FlyingEyeZones").is_physics_processing(), "Flying Eye controller remains available but inactive")
	var preview_key: InputEventKey = InputEventKey.new()
	preview_key.keycode = KEY_F6
	preview_key.physical_keycode = KEY_F6
	preview_key.pressed = true
	Input.parse_input_event(preview_key)
	await frames(2)
	var preview_applied: bool = int(zones.get("palette_variant")) == 1
	for pack: Node2D in zones.call("all_packs") as Array:
		for actor: InsectActor in pack.get("members") as Array:
			if int(actor.visual.get("palette_variant")) != 1: preview_applied = false
	check(preview_applied, "F6 switches the runtime palette on every loaded insect")
	preview_key.pressed = false
	Input.parse_input_event(preview_key)
	zones.call("set_palette_variant", 0)
	check((zones.get("zones") as Dictionary).size() == 20 and (zones.get("active_zones") as Array).size() == 2, "Insects reuse all twenty zones and keep only two loaded")
	var packs: Array = zones.call("all_packs") as Array
	check(not packs.is_empty() and packs.size() <= 4 and int(zones.call("live_count")) <= 12, "Mixed encounters spawn naturally within the twelve-insect budget")
	check((zones.get("altar_regions") as Array).size() == 6, "Insect habitat maps all six authored horde arenas")
	var near_paths: int = 0
	var candidates_total: int = 0
	for state: Dictionary in (zones.get("runtime") as Dictionary).values():
		near_paths += (state.path_candidates as Array).size()
		for point: Vector2 in state.candidates as Array:
			candidates_total += 1
			check(bool(zones.call("outside_altars", point, 34.0)), "Candidate stays outside the protected altar footprint")
	check(near_paths > 0 and candidates_total > near_paths, "Habitat offers preferred path candidates and open clearings")
	var safe: bool = true
	var logs: Array = zones.get("spawn_log") as Array
	for entry: Dictionary in logs:
		if int(entry.count) < 3 or int(entry.count) > 6: safe = false
		for point: Vector2 in entry.members as Array:
			var height: float = float(arena.get_node("TerrainElevation").call("height_at", point))
			if not bool(zones.call("supports_insects", point)) or (entry.viewport as Rect2).grow(56.0).has_point(point - Vector2(0, height + 8.0)): safe = false
	check(safe and not logs.is_empty(), "Every 3-6 member pack appears on valid floor outside the camera")
	await _inspect_spawned_pack(packs)
	var total_before: int = int(zones.get("spawn_total"))
	if not packs.is_empty():
		var first_pack: Node2D = packs[-1] as Node2D
		for actor: InsectActor in (first_pack.get("members") as Array).duplicate(): actor.take_damage(999.0)
		await frames(100)
		check(int(zones.get("spawn_total")) <= 4 and int(zones.call("live_count")) <= 12, "Pack losses preserve zone quotas and the global insect budget")
		total_before = int(zones.get("spawn_total"))
	var encounter: Node2D = (arena.get_node("SpiritHordes").get("encounters") as Array)[0] as Node2D
	player.position = encounter.get("arena_center") as Vector2
	player.snap_floor_height()
	encounter.call("begin")
	var stopped: bool = bool(zones.get("suspended"))
	for pack: Node2D in zones.call("all_packs") as Array:
		for actor: InsectActor in pack.get("members") as Array:
			if actor.engaged or actor.attack_in_progress(): stopped = false
	check(stopped, "Altar start synchronously cancels ambient insect attacks")
	await frames(60)
	check(int(zones.get("spawn_total")) == total_before, "Altar encounter suspends new exploration spawns")
	encounter.call("_on_player_defeated")
	await frames(3)
	check(not bool(zones.get("suspended")), "Aborting the altar resumes exploration")
	var evictions_before: int = int(zones.get("evictions"))
	for identifier: StringName in zones.get("zones") as Dictionary:
		if (zones.get("active_zones") as Array).has(identifier): continue
		var zone_rect: Rect2 = (zones.get("zones") as Dictionary)[identifier].rect as Rect2
		zones.call("_update_zones", zone_rect.get_center())
		break
	check(int(zones.get("evictions")) > evictions_before and (zones.get("active_zones") as Array).size() == 2, "Loading a third zone retires its oldest insect packs")
	await frames(3)
	check(get_nodes_in_group(&"insects").size() == int(zones.call("live_count")), "Zone retirement leaves no orphan insect bodies")
	report["world"] = {"zones": (zones.get("zones") as Dictionary).size(), "spawned_packs": zones.get("spawn_total"), "live_insects": zones.call("live_count"), "compositions": logs}
	arena.queue_free()
	await frames(4)


func _inspect_spawned_pack(packs: Array) -> void:
	if packs.is_empty(): return
	var selected: Node2D = packs[0] as Node2D
	for candidate: Node2D in packs:
		var kinds: Array = candidate.get("composition") as Array
		if kinds.has(&"tall") and kinds.has(&"fly"): selected = candidate
	player.position = (selected.get("anchor") as Vector2) + Vector2(-75, 40)
	player.snap_floor_height()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.5
	camera.force_update_scroll()
	report["showcase_composition"] = selected.get("composition")
	await frames(45)
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/insects/open_world.png")
	await frames(130)
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/insects/open_world_combat.png")


func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	world = Node2D.new()
	root.add_child(world)
	player = PLAYER.instantiate() as Player
	player.arena_bounds = Rect2(-1000, -1000, 6000, 6000)
	player.movement_bounds = player.arena_bounds
	world.add_child(player)
	player.add_child(PARRY.new() as Node2D)
	player.position = Vector2(800, 800)
	player.set_physics_process(false)
	player.get_node("BoosterShooter").set_process(false)
	await frames(3)
	_assets()
	await _combat_contract()
	await _tall()
	await _flies()
	await _littles()
	await _little_steering()
	await _death_remains()
	await _navigation_safety()
	await _integration()
	report["checks"] = checks
	report["failures"] = failures
	var output: FileAccess = FileAccess.open("res://output/insects/regression.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("INSECT_REGRESSION " + ("PASS " if failures.is_empty() else "FAIL ") + str(checks) + " checks")
	quit(0 if failures.is_empty() else 1)
