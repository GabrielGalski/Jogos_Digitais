extends SceneTree
## Exact block cost, last-platform recovery, enemy immunity and lethal low health.

const FLASH: Script = preload("res://scripts/bosses/elemental_golem/arena_flashes.gd")
var failures: Array[String] = []
var arena: Node2D = null
var player: Player = null
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


func ticks(count: int = 3) -> void:
	for index: int in range(count): await physics_frame
	await process_frame


func place(point: Vector2) -> void:
	player.position = point
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.reset_physics_interpolation()


func fall() -> void:
	var previous: float = player.health
	var layout: Node2D = arena.get_node("CastleLayout") as Node2D
	var platforms: Array = layout.get("platforms") as Array
	var left: Rect2 = platforms[3] as Rect2
	var middle: Rect2 = platforms[4] as Rect2
	place(Vector2((left.end.x+middle.position.x)*0.5,left.get_center().y)-Vector2(0,3))
	check(await wait_until(func() -> bool: return player.health<previous),"Void detection applies fall cost")


func capture(label: String) -> void:
	if not rendered: return
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://output/elemental_golem/falls")
	root.get_texture().get_image().save_png("res://output/elemental_golem/falls/"+label+".png")


func _run() -> void:
	root.size = Vector2i(960,540)
	root.content_scale_size = Vector2i(480,270)
	arena = (load("res://scenes/bosses/elemental_golem_arena.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	player = arena.get_node("Nox") as Player
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Arrival finishes")
	var boss: Node2D = arena.get_node("ElementalGolem") as Node2D
	boss.set_physics_process(false)
	var layout: Node2D = arena.get_node("CastleLayout") as Node2D
	var platforms: Array = layout.get("platforms") as Array
	var left: Rect2 = platforms[3] as Rect2
	place(left.get_center()-Vector2(0,3))
	await ticks()
	var last_floor: Vector2 = arena.get("last_safe_position") as Vector2
	var boss_health: float = float(boss.get("health"))
	await fall()
	check(is_equal_approx(player.health,50.0),"A full block costs exactly ten HP rather than rounded twelve")
	check(not player.dead and not bool(arena.get_node("PlayerDefeat").get("active")),"Ordinary fall keeps the player in combat")
	check(player.position.is_equal_approx(last_floor),"Fall returns to last platform location, not entrance warp")
	check(player.is_fall_recovery_invulnerable(),"Return grants brief recovery invulnerability")
	check(float(boss.get("health"))==boss_health and bool(arena.get("battle_started")),"Fall does not restart boss progress")
	var bar: Range = arena.get_node("PlayerHUD/Interface/SafeArea/Column/HP") as Range
	check(bar.value==50.0 and int(bar.get("lit_blocks"))==5,"HUD removes exactly one whole block")
	await capture("01_one_block_lost")
	player.receive_contact_damage(6,Vector2.RIGHT,100.0)
	check(not player.receive_projectile_damage(3),"Projectile damage rejects recovery protection")
	player.receive_skybreaker_hit(12.0)
	check(player.health==50.0 and player.knockback_velocity.is_zero_approx(),"Recovery blocks contact, knockback and direct special damage")
	var flash: Node2D = FLASH.new() as Node2D
	flash.set("target",player)
	var feet: Vector2 = player.position+Vector2(0,3)
	flash.set("segments",[PackedVector2Array([feet-Vector2(60,0),feet+Vector2(60,0)])] as Array[PackedVector2Array])
	flash.set("arrival_interval",0.0)
	flash.set("entry_duration",0.01)
	flash.set("warning_duration",0.01)
	flash.set("strike_duration",2.0)
	arena.get_node("BossAttacks").add_child(flash)
	flash.set_physics_process(false)
	flash.call("_physics_process",0.1)
	check(player.health==50.0 and not bool((flash.get("_hit_beams") as Array)[0]),"White cut cannot damage the protected recovery")
	check(await wait_until(func() -> bool: return not player.is_fall_recovery_invulnerable(),1.6),"Recovery protection expires after one second")
	flash.call("_physics_process",0.1)
	check(player.health==50.0,"A resolved cut cannot return after recovery protection expires")
	flash.call("cancel")
	await ticks(2)
	flash = FLASH.new() as Node2D
	flash.set("target",player)
	flash.set("segments",[PackedVector2Array([feet-Vector2(60,0),feet+Vector2(60,0)])] as Array[PackedVector2Array])
	flash.set("entry_duration",0.01)
	flash.set("warning_duration",0.01)
	arena.get_node("BossAttacks").add_child(flash)
	flash.set_physics_process(false)
	flash.call("_physics_process",0.1)
	check(player.health==38.0,"A new white cut can damage again after recovery expires")
	flash.call("cancel")
	await ticks(2)
	player.heal_full()
	player.receive_skybreaker_hit(10.0)
	check(player.health==48.0,"Other combat attacks preserve existing three-point damage rounding")
	player.heal_full()
	player.health = 57.0
	await fall()
	check(player.health==47.0,"Partially filled health still loses a whole ten-point block")
	# The next platform, even near its edge, replaces the previous recovery location.
	var middle: Rect2 = platforms[4] as Rect2
	place(middle.get_center()-Vector2(0,3))
	await ticks()
	var next_floor: Vector2 = arena.get("last_safe_position") as Vector2
	check(middle.grow(-8.0).has_point(next_floor) and next_floor!=last_floor,"Recovery point follows the next safe platform")
	await fall()
	check(player.health==37.0,"Another real fall costs another block during enemy protection")
	check(player.position.is_equal_approx(next_floor),"Return follows the new platform rather than the older platform")
	check(bool(arena.get_node("CastleLayout").call("supports_feet",player.to_global(Vector2(0,3)))),"Returned feet are on solid floor")
	player.heal_full()
	place(Vector2(left.end.x-14.0,left.get_center().y)-Vector2(0,3))
	await ticks()
	player.dash_charges = 2
	check(player.try_dash(Vector2.RIGHT),"Dash starts next to the gap")
	check(await wait_until(func() -> bool: return not player.is_dashing()),"Dash finishes")
	check(player.health==60.0 and middle.has_point(player.position),"Dash can cross void without fall damage")
	await ticks()
	var landed: Vector2 = arena.get("last_safe_position") as Vector2
	await fall()
	check(player.health==50.0 and player.position.is_equal_approx(landed),"A dash landing becomes the latest recovery location")
	player.max_health = 120.0
	player.heal_full()
	await fall()
	check(player.health==100.0,"Fall cost follows one of six blocks when maximum health changes")
	player.max_health = 60.0
	player.heal_full()
	player.health = 9.0
	await fall()
	check(player.dead and player.health==0.0,"Less than one block of health causes defeat")
	check(await wait_until(func() -> bool: return bool(arena.get_node("PlayerDefeat").get("menu_ready"))),"Lethal fall uses normal defeat menu")
	await capture("02_low_health_defeat")
	arena.get_node("PlayerDefeat").call("retry")
	var previous_id: int = arena.get_instance_id()
	check(await wait_until(func() -> bool: return current_scene.get_instance_id()!=previous_id),"Low-health fall can retry normally")
	arena = current_scene as Node2D
	player = arena.get_node("Nox") as Player
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))),"Retry arrival finishes")
	check(player.health==60.0 and not player.is_fall_recovery_invulnerable(),"Retry restores full health and clears old recovery state")
	player.health = 10.0
	await fall()
	check(player.dead and player.health==0.0,"Exactly one remaining block is exhausted by the fall")
	arena.queue_free()
	await ticks()
	check(not paused and is_equal_approx(Engine.time_scale,1.0),"Defeat cleanup restores the game clock")
	print("ELEMENTAL_GOLEM_FALL_REGRESSION "+("PASS" if failures.is_empty() else "FAIL "+str(failures.size())))
	quit(0 if failures.is_empty() else 1)
