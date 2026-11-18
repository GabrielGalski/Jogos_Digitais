extends SceneTree
## Independent white-to-element charges, ordered white cuts, one impact per line.
const FLASH: Script = preload("res://scripts/bosses/elemental_golem/arena_flashes.gd")
const BOSS: Script = preload("res://scripts/bosses/elemental_golem/elemental_golem.gd")
var failures: Array[String] = []
var arena: Node2D = null
var player: Player = null
var layout: Node2D = null
var boss: Node2D = null
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)


func wait_until(condition: Callable, seconds: float = 8.0) -> bool:
	var limit: int = Time.get_ticks_msec()+int(seconds*1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < limit: await process_frame
	return bool(condition.call())


func place(point: Vector2) -> void:
	player.position = point
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()


func capture(label: String) -> void:
	if not rendered: return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://output/elemental_golem/flashes")
	root.get_texture().get_image().save_png("res://output/elemental_golem/flashes/"+label+".png")


func advance(effect: Node2D, moment: float) -> void:
	effect.call("_physics_process",maxf(moment-float(effect.get("elapsed")),0.0))


func _run() -> void:
	root.size = Vector2i(960,540)
	root.content_scale_size = Vector2i(480,270)
	var map_hash: String = FileAccess.get_sha256("res://monster_booster.ldtk")
	arena = (load("res://scenes/bosses/elemental_golem_arena.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	layout = arena.get_node("CastleLayout") as Node2D
	boss = arena.get_node("ElementalGolem") as Node2D
	check(await wait_until(func() -> bool: return not player.intro_locked),"Arrival completes")
	arena.set_physics_process(false)
	player.set_physics_process(false)
	boss.set_physics_process(false)
	var center: Vector2 = ((layout.get("platforms") as Array)[4] as Rect2).get_center()
	boss.position = center
	boss.set("shielded",true)
	for element: int in range(3): await _visual_sequence(element,center)
	await _impact_contacts()
	await _integrated_specials(center)
	check(FileAccess.get_sha256("res://monster_booster.ldtk")==map_hash,"Flash changes preserve the authored LDtk")
	arena.queue_free()
	await process_frame
	print("ELEMENTAL_GOLEM_FLASH_REGRESSION "+("PASS" if failures.is_empty() else "FAIL "+str(failures.size())))
	quit(0 if failures.is_empty() else 1)


func _visual_sequence(element: int, center: Vector2) -> void:
	place(center+Vector2(-42,16))
	player.heal_full()
	boss.set("element",element)
	var sprite: AnimatedSprite2D = boss.get_node("Sprite") as AnimatedSprite2D
	sprite.sprite_frames = BOSS.FRAMES[element]
	sprite.play(&"idle")
	boss.queue_redraw()
	var effect: Node2D = FLASH.new() as Node2D
	effect.call("configure",player,layout,element,element+1)
	arena.get_node("BossAttacks").add_child(effect)
	effect.set_physics_process(false)
	var arrived: Array[int] = []
	var activated: Array[int] = []
	var completed: Array[int] = []
	effect.connect("beam_arrived",func(index: int) -> void: arrived.append(index))
	effect.connect("beam_activated",func(index: int) -> void: activated.append(index))
	effect.connect("beam_finished",func(index: int) -> void: completed.append(index))
	var segments: Array = effect.get("segments") as Array
	check(segments.size()==16,"Special fills the screen with sixteen cuts")
	var view: Rect2 = effect.get("_entry_view") as Rect2
	for segment: PackedVector2Array in segments:
		check(not view.has_point(segment[0]) and not view.has_point(segment[1]),"Cuts extend beyond the visible screen")
	advance(effect,0.20)
	check(arrived==[0] and activated.is_empty(),"White lines arrive in sequence")
	check(float(effect.call("charge_progress",0))<0.01,"Incoming cuts start white")
	await capture("element_%d_01_white_arrival" % element)
	advance(effect,0.75)
	check(arrived.size()>1 and arrived.size()<16,"Cuts do not appear together")
	check(player.health==player.max_health,"White preparation on the player is harmless")
	var first_cut: float = float(effect.call("activation_time",0))
	advance(effect,first_cut-0.08)
	check(arrived.size()==16 and activated.is_empty(),"The screen fills before the first cut")
	check(float(effect.call("charge_progress",0))>0.95 and float(effect.call("charge_progress",15))<0.15,"Earlier cuts are elemental while newer cuts remain almost white")
	check(player.health==player.max_health,"Elemental colour is still a harmless warning")
	await capture("element_%d_02_colour_gradient" % element)
	advance(effect,first_cut+0.01)
	check(activated==[0],"The first white flash cuts independently")
	check(is_equal_approx(player.health,player.max_health*0.8),"Final white cut deals twenty percent health")
	await capture("element_%d_03_white_cut" % element)
	advance(effect,first_cut+0.05)
	check(is_equal_approx(player.health,player.max_health*0.8),"The bright cut is a single impact")
	var fixed_segments: Array = segments.duplicate(true)
	var safe: Vector2 = effect.get("safe_point") as Vector2
	place(safe-Vector2(0,3))
	advance(effect,float(effect.call("completion_time",0))+0.01)
	check(completed==[0] and activated==[0,1],"First line disappears while the second cuts and later lines keep charging")
	check(int(effect.call("hit_count",safe))==0 and bool(layout.call("supports_feet",safe)),"Dense pattern preserves reachable safe ground")
	check((effect.get("segments") as Array)==fixed_segments,"Moving the camera does not move the cuts")
	await capture("element_%d_04_ordered_disappearance" % element)
	advance(effect,float(effect.call("activation_time",15))+0.01)
	check(activated.size()==16 and completed.size()<16,"Last cut occurs after earlier lines have vanished")
	check(is_equal_approx(player.health,player.max_health*0.8),"Standing off every line takes no further damage")
	advance(effect,float(effect.call("total_duration"))+0.01)
	check(arrived==activated and activated==completed and completed.size()==16,"Arrival, cut and disappearance have the same order")
	await process_frame


func _manual_effect(lines: Array[PackedVector2Array], interval: float = 0.0) -> Node2D:
	var effect: Node2D = FLASH.new() as Node2D
	effect.set("target",player)
	effect.set("segments",lines)
	effect.set("arrival_interval",interval)
	effect.set("entry_duration",0.01)
	effect.set("warning_duration",0.30)
	arena.get_node("BossAttacks").add_child(effect)
	effect.set_physics_process(false)
	return effect


func _impact_contacts() -> void:
	var horizontal: PackedVector2Array = PackedVector2Array([Vector2(-80,63),Vector2(80,63)])
	var vertical: PackedVector2Array = PackedVector2Array([Vector2(0,20),Vector2(0,110)])
	place(Vector2(0,60))
	player.heal_full()
	var effect: Node2D = _manual_effect([horizontal,vertical])
	advance(effect,0.30)
	check(player.health==player.max_health,"No damage before white impact, including at intersections")
	advance(effect,0.32)
	check(is_equal_approx(player.health,player.max_health*0.6),"Two white cuts cause two independent twenty-percent hits")
	player.heal_full()
	advance(effect,0.35)
	check(player.health==player.max_health,"A cut never hits twice during its brightness")
	effect.call("cancel")
	await process_frame
	# Outside the visible 18px line is safe; entering after impact is safe too.
	place(Vector2(0,69.1))
	effect = _manual_effect([horizontal])
	advance(effect,0.32)
	check(player.health==player.max_health,"No hidden damage margin outside the drawn line")
	place(Vector2(0,60))
	advance(effect,0.36)
	check(player.health==player.max_health,"Entering a white remnant after the cut does not deal late damage")
	advance(effect,0.50)
	check(player.health==player.max_health,"Disappearing lines are harmless")
	effect.call("cancel")
	await process_frame
	# Dash and fall immunity protect the instantaneous cut, not a persistent beam.
	player.dash_charges = 2
	check(player.try_dash(Vector2.RIGHT),"Dash opens its real defence window")
	effect = _manual_effect([horizontal])
	advance(effect,0.32)
	check(player.health==player.max_health,"Dash avoids the cut")
	player.dash_remaining = 0.0
	player.body.end_roll()
	advance(effect,0.36)
	check(player.health==player.max_health,"Missed cut does not hit after dash ends")
	effect.call("cancel")
	await process_frame
	player.grant_fall_recovery(1.0)
	effect = _manual_effect([horizontal])
	advance(effect,0.32)
	check(player.health==player.max_health,"Fall recovery protects from the white impact")
	player.fall_recovery_remaining = 0.0
	advance(effect,0.36)
	check(player.health==player.max_health,"Resolved cut does not return after immunity ends")
	effect.call("cancel")
	await process_frame
	# The same intersection can be cut again by a later, independently timed line.
	effect = _manual_effect([horizontal,vertical],0.16)
	advance(effect,0.32)
	check(is_equal_approx(player.health,player.max_health*0.8),"First staggered cut deals one hit")
	advance(effect,0.48)
	check(is_equal_approx(player.health,player.max_health*0.6),"Later cut independently hits the same intersection")
	effect.call("cancel")
	await process_frame


func _integrated_specials(center: Vector2) -> void:
	boss.set("shielded",false)
	boss.set("state",BOSS.State.RECOVERING)
	boss.set_physics_process(true)
	for sequence: int in range(1,4):
		place(center+Vector2(-42,16))
		player.heal_full()
		boss.call("take_damage",9999.0)
		check(bool(boss.get("shielded")),"Quarter-health gate immediately protects the boss")
		check(await wait_until(func() -> bool: return int(boss.get("state"))==BOSS.State.SPECIAL),"Shielded golem jumps to centre and holds idle")
		var effect: Node2D = boss.get("flashes") as Node2D
		check(is_instance_valid(effect),"Actual special creates the new flash effect")
		if not is_instance_valid(effect): return
		check(int(effect.get("element"))==sequence-1,"All three special elements use the new sequence")
		var health: float = float(boss.get("health"))
		boss.call("take_damage",30.0)
		check(float(boss.get("health"))==health,"Golem remains invulnerable during the sequence")
		place((effect.get("safe_point") as Vector2)-Vector2(0,3))
		check(await wait_until(func() -> bool: return not bool(boss.get("shielded"))),"Last disappearing cut releases the shield")
		check(player.health==player.max_health,"Safe floor survives the full real-time special")
	boss.call("stop_combat")
