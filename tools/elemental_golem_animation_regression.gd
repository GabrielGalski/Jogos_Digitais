extends SceneTree
## Real volley contacts follow mapped slam poses; death becomes static room scenery.
const BOSS: Script = preload("res://scripts/bosses/elemental_golem/elemental_golem.gd")
const ATTACK: Script = preload("res://scripts/bosses/elemental_golem/attack_frames.gd")
var failures: Array[String] = []
var arena: Node2D = null
var boss: CharacterBody2D = null
var player: Player = null
var times: Array[float] = []
var finish_count: int = 0
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func wait_until(condition: Callable, seconds: float = 4.0) -> bool:
	var deadline: int = Time.get_ticks_msec()+int(seconds*1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec()<deadline: await process_frame
	return bool(condition.call())


func _record_volley(element: int, volley: int) -> void:
	var sprite: AnimatedSprite2D = boss.get("sprite") as AnimatedSprite2D
	check(sprite.animation==&"slam" and sprite.frame==ATTACK.SLAM_IMPACT_FRAME,"Volley releases on the ground contact frame")
	check(sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)==sprite.sprite_frames.get_frame_texture(&"attack",6),"Contact is authored source pose 7")
	check(volley==times.size(),"Each contact emits exactly one indexed volley")
	times.append(float(boss.get("_barrage_elapsed")))
	var active: Array[Node] = []
	for orb: Node in arena.get_node("BossAttacks").get_children():
		if not orb.is_queued_for_deletion(): active.append(orb)
	check(active.size()==[8,3,1][element],"Contact spawns the existing elemental pattern")
	for orb: Node in active:
		check(int(orb.get("element"))==element,"Contact retains its elemental palette")
		check((orb as Node2D).global_position.distance_to(boss.global_position+ATTACK.MUZZLE)<18.01,"Shots originate at the slam's hands")


func capture(label: String) -> void:
	if not rendered: return
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://output/elemental_golem/animations")
	root.get_texture().get_image().save_png("res://output/elemental_golem/animations/"+label+".png")


func _run() -> void:
	root.size = Vector2i(960,540)
	root.content_scale_size = Vector2i(480,270)
	arena = (load("res://scenes/bosses/elemental_golem_arena.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	boss = arena.get_node("ElementalGolem") as CharacterBody2D
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Arrival finishes")
	arena.set_physics_process(false)
	player.set_physics_process(false)
	player.grant_fall_recovery(100.0)
	player.position = Vector2(-48,-36)
	player.reset_physics_interpolation()
	boss.set_physics_process(false)
	boss.position = Vector2(20,-88)
	boss.set("current_platform",4)
	boss.connect("volley_fired",_record_volley)
	var sprite: AnimatedSprite2D = boss.get("sprite") as AnimatedSprite2D
	for element: int in range(3):
		sprite.sprite_frames = BOSS.FRAMES[element]
		var frames: SpriteFrames = sprite.sprite_frames
		check(frames.get_frame_count(&"die")==12 and frames.get_frame_texture(&"die",11).get_image().get_used_rect().has_area(),"Every element has a visible terminal death texture")
		for clip: String in ATTACK.CLIPS:
			check(frames.get_frame_count(clip)==(ATTACK.CLIPS[clip] as Array).size(),"All elements contain the complete mapped clips")
			for index: int in range(frames.get_frame_count(clip)):
				check(frames.get_frame_texture(clip,index)==frames.get_frame_texture(&"attack",int(ATTACK.CLIPS[clip][index])),"Clip textures preserve authored pose order")
		times.clear()
		boss.set("element",element)
		boss.set("last_firing_platform",-1)
		boss.call("_start_barrage")
		check(sprite.animation==&"slam" and sprite.frame==0,"Barrage begins with the raised-arm pose")
		var captured: bool = false
		while int(boss.get("state"))==BOSS.State.FIRING:
			var before_count: int = times.size()
			boss.call("_physics_process",1.0/240.0)
			if not captured and times.size()==1:
				captured = true
				await capture("element_%d_impact" % element)
			boss.call("clear_attacks")
			if times.size()>before_count: await process_frame
		var interval: float = ATTACK.VOLLEY_INTERVALS[element]
		check(times.size()==[5,6,5][element],"Barrage keeps the element's firing cadence and time limit")
		for index: int in range(times.size()):
			var expected: float = interval*(float(index)+1.0/11.0)
			check(absf(times[index]-expected)<0.005,"Every visual impact stays in time with its volley without drift")
		var count: int = times.size()
		boss.call("_physics_process",0.1)
		check(times.size()==count,"Finishing the barrage cancels further releases")
	# Interrupt just before impact; no delayed projectile may survive the special.
	times.clear()
	boss.set("last_firing_platform",-1)
	boss.call("_start_barrage")
	boss.call("_physics_process",0.005)
	boss.call("take_damage",9999.0)
	boss.call("_physics_process",0.25)
	check(times.is_empty() and arena.get_node("BossAttacks").get_child_count()==0,"Special interruption cancels the pending impact")
	boss.set("shielded",false)
	boss.set("special_count",3)
	boss.set("state",BOSS.State.RECOVERING)
	boss.set("element",2)
	sprite.sprite_frames = BOSS.FRAMES[2]
	boss.set("air_height",35.0)
	sprite.position.y = -35.0
	sprite.flip_h = true
	boss.position = Vector2(34,-65)
	boss.connect("defeat_animation_finished",func() -> void: finish_count += 1)
	boss.call("take_damage",9999.0)
	check(sprite.animation==&"die" and sprite.position==Vector2.ZERO,"Death starts grounded at the actual defeat point")
	check(not arena.has_node("ElementalGolemRemains"),"Room object waits for the authored death sequence")
	check(await wait_until(func() -> bool: return arena.has_node("ElementalGolemRemains")),"Completed death creates static scenery")
	var remains: Sprite2D = arena.get_node("ElementalGolemRemains") as Sprite2D
	check(sprite.sprite_frames.get_frame_count(&"die")==12,"Runtime death omits the trailing transparent cell")
	check(remains.texture==sprite.sprite_frames.get_frame_texture(&"die",11),"Room object uses exactly the last visible die pose 12")
	check(remains.texture.get_image().get_used_rect().has_area(),"Defeated scenery contains visible pixels")
	check(remains.position.is_equal_approx(Vector2(34,-65)) and remains.scale.is_equal_approx(Vector2(1.6,1.6)),"Rubble preserves defeat location and authored visual size")
	check(remains.offset==sprite.offset and remains.flip_h,"Rubble preserves the feet pivot and facing")
	check(boss.collision_layer==0 and not boss.is_in_group(&"enemy_bodies") and not boss.is_physics_processing(),"Defeated actor no longer participates in combat")
	check(not boss.visible and finish_count==1,"Death hands presentation to one room object")
	await create_timer(0.6).timeout
	boss.call("stop_combat")
	check(finish_count==1 and is_instance_valid(remains) and remains.modulate==Color.WHITE,"Rubble persists without fading or duplicate finish events")
	await capture("defeated_room_object")
	var previous: WeakRef = weakref(remains)
	arena.queue_free()
	await process_frame
	check(previous.get_ref()==null and get_nodes_in_group(&"room_boss_remains").is_empty(),"Room teardown releases its defeated scenery")
	await _interrupted_death()
	print("ELEMENTAL_GOLEM_ANIMATION_REGRESSION "+("PASS" if failures.is_empty() else "FAIL "+str(failures.size())))
	quit(0 if failures.is_empty() else 1)


func _interrupted_death() -> void:
	arena = (load("res://scenes/bosses/elemental_golem_arena.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	boss = arena.get_node("ElementalGolem") as CharacterBody2D
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Second arrival finishes")
	boss.set("state",BOSS.State.RECOVERING)
	boss.set("special_count",3)
	boss.call("take_damage",9999.0)
	player.receive_skybreaker_hit(9999.0)
	check(arena.has_node("ElementalGolemRemains"),"Player defeat during die safely finishes the static room object")
	var checkpoint: Dictionary = arena.get_node("PlayerDefeat").get("_checkpoint_properties") as Dictionary
	check(bool(checkpoint.boss_already_defeated) and not (checkpoint.boss_remains_state as Dictionary).is_empty(),"Victory checkpoint already contains the rubble position before die finishes")
	arena.queue_free()
	await process_frame
	check(not paused and is_equal_approx(Engine.time_scale,1.0),"Interrupted defeat teardown restores the game clock")
