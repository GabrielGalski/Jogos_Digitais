extends SceneTree
## Real arena and world integration: hazards, parry, phase gates and preserved return.

const BOSS: Script = preload("res://scripts/bosses/elemental_golem/elemental_golem.gd")
const FLASH: Script = preload("res://scripts/bosses/elemental_golem/arena_flashes.gd")
const ORB: Script = preload("res://scripts/bosses/elemental_golem/elemental_orb.gd")
var failures: Array[String] = []
var rendered: bool = false
var arena: Node2D = null
var subject: Player = null
var boss: CharacterBody2D = null


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func wait_until(condition: Callable, seconds: float = 6.0) -> bool:
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(condition.call())


func ticks(count: int = 3) -> void:
	for index: int in range(count): await physics_frame
	await process_frame


func place(point: Vector2) -> void:
	subject.position = point
	subject.velocity = Vector2.ZERO
	subject.knockback_velocity = Vector2.ZERO
	subject.contact_invulnerability = 0.0
	subject.reset_physics_interpolation()
	var camera: Camera2D = subject.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()


func capture(label: String, overview: bool = false) -> void:
	if not rendered: return
	var camera: Camera2D = null
	var previous: Camera2D = root.get_camera_2d()
	if overview:
		camera = Camera2D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var area: Rect2 = (arena.get_node("CastleLayout").get("bounds") as Rect2).grow(32.0)
		camera.position = area.get_center()
		camera.zoom = Vector2.ONE*minf(root.get_visible_rect().size.x/area.size.x,root.get_visible_rect().size.y/area.size.y)
		arena.add_child(camera)
		camera.make_current()
		camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://output/elemental_golem")
	root.get_texture().get_image().save_png("res://output/elemental_golem/"+label+".png")
	if camera != null:
		camera.queue_free()
		previous.make_current()
		previous.reset_smoothing()
		previous.force_update_scroll()
	await process_frame


func _run() -> void:
	root.size = Vector2i(960,540)
	if "--world-only" not in OS.get_cmdline_user_args():
		_asset_checks()
		await _arena_checks()
	if "--arena-only" not in OS.get_cmdline_user_args(): await _world_checks()
	print("ELEMENTAL_GOLEM_REGRESSION "+("PASS" if failures.is_empty() else "FAIL "+str(failures.size())))
	quit(0 if failures.is_empty() else 1)


func _asset_checks() -> void:
	print("[GOLEM CHECK] 138 frames, alpha, stone and source hashes")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/enemies/golem/sprite_map.json")) as Dictionary
	var crystal_colors: Array = manifest.crystal_source_colors as Array
	for action: String in manifest.animations:
		var source_path: String = str(manifest.animations[action].source)
		check(FileAccess.get_sha256(source_path)==str(manifest.animations[action].sha256),"Authored source sheet remains intact")
		var source: Image = _png(source_path)
		for frame_index: int in range(int(manifest.animations[action].frames)):
			var original: Image = source.get_region(Rect2i(frame_index*90,0,90,64))
			for element_name: String in ["ice","fire","lightning"]:
				var path: String = "res://assets/enemies/golem/frames/%s/%s/%s_%02d.png" % [element_name,action,action,frame_index+1]
				var frame: Image = _png(path)
				check(frame.get_size()==Vector2i(90,64),"Every frame shares the authored canvas")
				var invariant: bool = true
				for y: int in range(64):
					for x: int in range(90):
						var old_pixel: Color = original.get_pixel(x,y)
						var new_pixel: Color = frame.get_pixel(x,y)
						if old_pixel.a!=new_pixel.a: invariant=false
						if element_name=="ice" or not crystal_colors.has(old_pixel.to_html(false)):
							if old_pixel!=new_pixel: invariant=false
						elif old_pixel.a>0.0 and old_pixel==new_pixel: invariant=false
				check(invariant,"Palette variants preserve alpha, stone and exact original ice pixels")


func _png(path: String) -> Image:
	var result: Image = Image.new()
	check(result.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK,"Frame PNG decodes")
	return result


func _arena_checks() -> void:
	print("[GOLEM CHECK] arena, barrages and parry")
	arena = (load("res://scenes/bosses/elemental_golem_arena.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	subject = arena.get_node("Nox") as Player
	boss = arena.get_node("ElementalGolem") as CharacterBody2D
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Castle arrival unlocks controls")
	check(not bool(arena.get("battle_started")),"Boss waits for player to leave entry hall")
	check((arena.get_node("CastleLayout").get("platforms") as Array).size()==9,"Castle has nine separate platforms")
	check((arena.get_node("CastleLayout").get("hall") as Rect2).size==Vector2(224,384),"Entrance corridor preserves its current size in LDtk")
	check(bool(arena.get_node("CastleLayout").call("supports_feet",Vector2(0,420))),"Extended corridor has physical floor support")
	check(not bool(arena.get_node("CastleLayout").call("supports_feet",Vector2(200,300))),"Former water areas are void")
	check(not arena.get_node("CastleLayout").has_node("CastleWater"),"Arena creates no water surface")
	check(arena.get_node("CastleLayout").has_node("Floor_Elemental_0"),"Arena renders the authored LDtk dungeon floor")
	check(not arena.get_node("EntranceWarp").find_children("*","Sprite2D",true,false).is_empty(),"Entrance uses the shared LDtk warp presentation")
	var camera: Camera2D = subject.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	await ticks(2)
	check(camera.zoom.is_equal_approx(Vector2(0.96,0.96)),"Arena preserves the production gameplay camera distance")
	check(subject.body.scale.is_equal_approx(Vector2(1.05,1.05)),"Nox retains the canonical gameplay scale")
	var screen_feet: Vector2 = subject.get_global_transform_with_canvas().origin
	var expected_feet: Vector2 = root.get_visible_rect().size*0.5-Vector2(0,4)*camera.zoom
	check(screen_feet.distance_to(expected_feet)<1.0,"Entrance camera keeps Nox at the world-map screen anchor")
	check(int(subject.get_node("BoosterShooter").get("z_index"))==-2,"Weapon depth matches the world-map player")
	await capture("00_entry_gameplay")
	await capture("01_castle_overview",true)
	place(Vector2(0,70))
	check(await wait_until(func() -> bool: return int(boss.get("state"))==BOSS.State.FIRING),"Approach starts first barrage")
	check((boss.get("sprite") as AnimatedSprite2D).animation==&"slam","Barrage uses the mapped ground-slam cycle")
	check(boss.call("get_combat_faction")==&"monsters","Boss participates in existing weapon contacts")
	await create_timer(0.85).timeout
	await capture("02_fire_barrage",true)
	await capture("02b_fire_gameplay")
	# Early termination uses actual damage from this barrage, not prior hits or HP loss.
	var serial: int = int(boss.get("_barrage_serial"))
	boss.call("_on_orb_damage",subject.max_health*0.15,serial-1)
	check(int(boss.get("state"))==BOSS.State.FIRING,"Old barrage damage cannot cancel new barrage")
	boss.call("_on_orb_damage",subject.max_health*0.15,serial)
	check(int(boss.get("state"))==BOSS.State.RECOVERING,"Fifteen percent damage stops firing")
	boss.call("clear_attacks")
	# Script the next three real cycles while the subject remains protected from bullets.
	var history_start: int = (boss.get("barrage_history") as Array).size()
	while (boss.get("barrage_history") as Array).size() < history_start+3:
		subject.contact_invulnerability = 3.0
		await physics_frame
	var history: Array = boss.get("barrage_history") as Array
	for index: int in range(1,history.size()): check(history[index]!=history[index-1],"Consecutive barrages use distinct platforms")
	check(history.size()>=4,"AI completes multiple timed barrage/leap cycles")
	boss.call("clear_attacks")
	boss.set_physics_process(false)
	# All elements expose the same parry contract and preserve their element on return.
	for element_index: int in range(3):
		place(Vector2(0,60))
		var orb: Node2D = ORB.new() as Node2D
		orb.set("target",subject)
		orb.set("caster",boss)
		orb.set("element",element_index)
		orb.set("direction",Vector2.DOWN)
		orb.position = subject.position+Vector2(0,-9)
		arena.get_node("BossAttacks").add_child(orb)
		subject.parry.call("cancel")
		subject.parry.set("recovery",0.0)
		check(subject.try_parry(),"Right-click parry opens a real defence window")
		check(bool(orb.get("reflected")),"Each elemental orb reflects through existing parry")
		check(float(orb.get("speed"))>=315.0,"Reflected elemental energy returns at high speed")
		check(int(orb.get("element"))==element_index,"Parry preserves the element")
		orb.call("dismiss")
		subject.parry.call("cancel")
		await ticks(2)
	# Swept return actually damages the caster, rather than just changing visuals.
	place(Vector2(0,60))
	var returned: Node2D = ORB.new() as Node2D
	returned.set("target",subject)
	returned.set("caster",boss)
	returned.position = boss.position+Vector2(0,36)
	arena.get_node("BossAttacks").add_child(returned)
	returned.call("parry",subject)
	var before: float = float(boss.get("health"))
	check(await wait_until(func() -> bool: return float(boss.get("health"))<before),"Returned orb damages the golem")
	boss.call("clear_attacks")
	# Force each threshold with a deliberately oversized hit: none may be skipped.
	for sequence: int in range(1,4):
		print("[GOLEM CHECK] special threshold ",sequence)
		place(Vector2(0,60))
		boss.set_physics_process(true)
		boss.call("take_damage",9999.0)
		check(is_equal_approx(float(boss.get("health")),360.0*(1.0-float(sequence)*0.25)),"Damage stops at each 25 percent phase gate")
		check(bool(boss.get("shielded")),"Threshold immediately grants invulnerability")
		var protected_health: float = float(boss.get("health"))
		boss.call("take_damage",30.0)
		check(float(boss.get("health"))==protected_health,"Shield rejects damage during special leap")
		check(await wait_until(func() -> bool: return int(boss.get("state"))==BOSS.State.SPECIAL),"Threshold leaps to centre before flashes")
		check(boss.position.is_equal_approx(Vector2(0,-88)),"Special uses centre platform")
		check((boss.get("sprite") as AnimatedSprite2D).animation==&"idle","Shielded special holds idle")
		var flashes: Node2D = boss.get("flashes") as Node2D
		var safe: Vector2 = flashes.get("safe_point") as Vector2
		check(bool(arena.get_node("CastleLayout").call("supports_feet",safe)),"Every flash pattern leaves reachable solid ground")
		check(int(flashes.call("hit_count",safe))==0,"Guaranteed safe point avoids every strip")
		place(safe-Vector2(0,3))
		if sequence==1: await capture("03_ice_special_warning",true)
		if sequence==2: await capture("04_fire_special_warning",true)
		if sequence==3: await capture("05_lightning_special_warning",true)
		var health_before: float = subject.health
		if sequence==3:
			check(await wait_until(func() -> bool: return bool(flashes.get("fired"))),"Lightning special reaches its visible impact")
			await capture("06_lightning_special_impact",true)
		check(await wait_until(func() -> bool: return not bool(boss.get("shielded")),8.0),"Special ends and removes shield")
		check(subject.health==health_before,"Standing outside strips takes no flash damage")
		boss.set_physics_process(false)
	check(int(boss.get("special_count"))==3,"Exactly three specials at 75, 50 and 25 percent")
	# Two simultaneous strips must deal 40%, with no projectile i-frame suppression.
	place(Vector2(0,60))
	subject.health = subject.max_health
	var overlap: Node2D = FLASH.new() as Node2D
	overlap.set("target",subject)
	overlap.set("segments",[PackedVector2Array([Vector2(-80,63),Vector2(80,63)]),PackedVector2Array([Vector2(0,20),Vector2(0,100)])] as Array[PackedVector2Array])
	overlap.set("warning_duration",0.08)
	overlap.set("arrival_interval",0.0)
	overlap.set("entry_duration",0.01)
	arena.get_node("BossAttacks").add_child(overlap)
	check(await wait_until(func() -> bool: return bool(overlap.get("fired"))),"Flash volley detonates")
	check(is_equal_approx(subject.health,subject.max_health*0.60),"Two intersecting flashes deal forty percent health")
	overlap.call("cancel")
	# Dash crosses the channel freely; a fall is lethal only at insufficient health.
	place(Vector2(-132,60))
	subject.dash_charges = 2
	check(subject.try_dash(Vector2.RIGHT),"Dash starts beside a platform gap")
	check(await wait_until(func() -> bool: return not subject.is_dashing()),"Dash finishes across the gap")
	check(not subject.dead and subject.position.x > -96.0,"Small gap can be crossed by dash")
	boss.call("take_damage",9999.0)
	check(bool(arena.get("won")),"Boss dies after final phase and clears encounter")
	check(arena.get_node("BossAttacks").get_child_count()==0 or await wait_until(func() -> bool: return arena.get_node("BossAttacks").get_child_count()==0),"Victory clears outstanding attacks")
	check(await wait_until(func() -> bool: return arena.has_node("ElementalGolemRemains")),"Final death frame becomes a room object")
	var remains: Sprite2D = arena.get_node("ElementalGolemRemains") as Sprite2D
	var remains_transform: Transform2D = remains.transform
	var remains_texture: Texture2D = remains.texture
	var old_remains: WeakRef = weakref(remains)
	check(not boss.visible and boss.collision_layer==0,"Defeated actor has no visible duplicate or active collision")
	subject.health = 9.0
	place(Vector2(-108,60))
	check(await wait_until(func() -> bool: return subject.dead),"Falling with less than one block causes defeat")
	var defeat: CanvasLayer = arena.get_node("PlayerDefeat") as CanvasLayer
	check(await wait_until(func() -> bool: return bool(defeat.get("menu_ready"))),"Fall offers retry menu")
	check(defeat.has_node("RetryMenu/Content/LeaveArena"),"Defeat offers exit to open world")
	await capture("07_fall_retry_menu")
	defeat.call("retry")
	var old_id: int = arena.get_instance_id()
	check(await wait_until(func() -> bool: return current_scene.get_instance_id()!=old_id),"Retry recreates castle at entrance")
	arena = current_scene as Node2D
	subject = arena.get_node("Nox") as Player
	check(subject.health==subject.max_health and not subject.dead,"Retry restores full health")
	check(subject.position.distance_to(arena.get_node("CastleLayout").get("entrance") as Vector2)<16.0,"Retry returns to the LDtk entrance warp")
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Retry arrival unlocks")
	check(bool(arena.get("won")) and arena.has_node("ElementalGolemRemains"),"Retry after victory keeps the defeated boss as scenery")
	remains = arena.get_node("ElementalGolemRemains") as Sprite2D
	check(remains.transform.is_equal_approx(remains_transform) and remains.texture==remains_texture,"Retry preserves the actual defeat location and elemental rubble")
	check(old_remains.get_ref()==null,"Recreating the room releases the previous room object")
	arena.queue_free()
	await ticks(3)
	check(not paused and is_equal_approx(Engine.time_scale,1.0),"Retry and teardown restore clock")


func press_e() -> void:
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_E
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)


func _world_checks() -> void:
	print("[GOLEM CHECK] world unlock, retry, exit and re-entry")
	var world: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	var journey: Node = world.get_node("ElementalBossJourney")
	var original: Player = world.get_node("Nox") as Player
	check(await wait_until(func() -> bool: return not original.intro_locked),"Open-world arrival unlocks")
	check(journey.get("gate")==null,"Boss warp is absent before the correct altar clears")
	var hordes: Array = world.get_node("SpiritHordes").get("encounters") as Array
	for encounter: Node2D in hordes:
		if str(encounter.get("encounter_id"))=="room_2_forest_west": encounter.call("skip_to_completion")
	check(journey.get("gate")==null,"Other altars cannot unlock the elemental boss")
	(journey.get("encounter") as Node2D).call("skip_to_completion")
	var gate: Node2D = journey.get("gate") as Node2D
	check(is_instance_valid(gate),"Lower-right altar completion reveals boss warp")
	check(bool(world.call("is_ground_surface_point",gate.global_position)),"New boss warp is on valid authored terrain")
	original.position = gate.call("spawn_position") as Vector2
	original.reset_physics_interpolation()
	await ticks(3)
	check(bool(gate.call("can_interact")),"Unlocked boss warp accepts E")
	press_e()
	check(await wait_until(func() -> bool: return current_scene!=world),"E travels into the elemental castle")
	arena = current_scene as Node2D
	subject = arena.get_node("Nox") as Player
	boss = arena.get_node("ElementalGolem") as CharacterBody2D
	check(not world.visible,"Original world stays suspended behind castle")
	check(original.collision_layer==0,"Suspended world colliders cannot enter the arena")
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Portal arrival finishes")
	# Die, retry with the same suspended world, die again and take the exit button.
	subject.health = 9.0
	place(Vector2(-108,60))
	check(await wait_until(func() -> bool: return bool(arena.get_node("PlayerDefeat").get("menu_ready"))),"Fatal fall during journey opens menu")
	arena.get_node("PlayerDefeat").call("retry")
	var old_id: int = arena.get_instance_id()
	check(await wait_until(func() -> bool: return current_scene.get_instance_id()!=old_id),"Journey retry creates fresh boss attempt")
	arena = current_scene as Node2D
	subject = arena.get_node("Nox") as Player
	check(arena.get("return_controller")==journey,"Retry preserves original world return route")
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Journey retry arrival finishes")
	subject.health = 9.0
	place(Vector2(-108,60))
	check(await wait_until(func() -> bool: return bool(arena.get_node("PlayerDefeat").get("menu_ready"))),"Second fall still offers exit")
	arena.get_node("PlayerDefeat").call("_leave_arena")
	check(await wait_until(func() -> bool: return current_scene==world),"Defeat exit returns to the actual open world")
	check(await wait_until(func() -> bool: return not original.intro_locked),"Return arrival unlocks original player")
	check(world.visible and original.collision_layer!=0,"Return restores world visibility and physics")
	check(int((journey.get("encounter") as Node).get("phase"))==2,"Completed altar remains completed after retry and exit")
	check(is_instance_valid(journey.get("gate") as Node),"Boss warp remains available after leaving")
	check(original.health==original.max_health,"Leaving after a fatal fall restores exploration health")
	press_e()
	check(await wait_until(func() -> bool: return current_scene!=world),"Player can re-enter unlocked boss warp")
	arena = current_scene as Node2D
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Re-entry arrival finishes")
	check(bool(arena.get_node("EntranceWarp").call("can_interact")),"LDtk arena warp accepts interaction after arrival")
	# A victory keeps rubble for this visit only; later visits do not replay death.
	boss = arena.get_node("ElementalGolem") as CharacterBody2D
	boss.set("state",BOSS.State.RECOVERING)
	boss.set("special_count",3)
	boss.position = Vector2(30,-65)
	boss.call("take_damage",9999.0)
	check(await wait_until(func() -> bool: return arena.has_node("ElementalGolemRemains")),"World journey also creates defeated scenery at victory")
	var old_remains: WeakRef = weakref(arena.get_node("ElementalGolemRemains"))
	press_e()
	check(await wait_until(func() -> bool: return current_scene==world),"Living player can leave via entry warp")
	check(await wait_until(func() -> bool: return not original.intro_locked),"Second return restores controls")
	check(old_remains.get_ref()==null and get_nodes_in_group(&"room_boss_remains").is_empty(),"Leaving the arena frees its rubble with the room")
	press_e()
	check(await wait_until(func() -> bool: return current_scene!=world),"Completed boss warp still permits a later visit")
	arena = current_scene as Node2D
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Completed arena arrival finishes")
	check(bool(arena.get("won")) and not arena.has_node("ElementalGolemRemains"),"New visit preserves victory without carrying old rubble")
	check(not (arena.get_node("ElementalGolem") as CanvasItem).visible,"New visit does not replay the defeated enemy")
	arena.call("leave_arena")
	check(await wait_until(func() -> bool: return current_scene==world),"Completed arena still returns through the warp")
	check(await wait_until(func() -> bool: return not original.intro_locked),"Completed return restores the original player")
	world.queue_free()
	await ticks(3)
