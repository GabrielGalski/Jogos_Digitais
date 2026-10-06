extends SceneTree

var skybreaker_count := 0
var area_count := 0
var melee_count := 0
var player_hit_count := 0


func _initialize() -> void:
	call_deferred("run")


func press_space() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	Input.parse_input_event(event)


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/asterion_alignment_" + label + ".png")


func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena = main.get_node("TutorialArena")
	var boss = arena.get_node("MinotaurChair")
	var player = arena.get_node("Mox")
	var camera = player.get_node("Camera2D")
	for left in [false, true]:
		boss.facing_left = left
		boss._set_ground_pose(boss.WALK_FRAMES[0])
		var foot_x := 64.0 - 25.0 if left else 25.0
		assert(boss.visual.to_global(Vector2(foot_x, 48) + boss.visual.offset).is_equal_approx(boss.actor.global_position))
		for texture in boss.MELEE_ATTACK_FRAMES:
			boss._set_attack_pose(texture)
			assert(is_equal_approx(boss.visual.offset.y, -48.0), "Attack effects must not lift the feet")
	boss.facing_left = false
	assert(boss.shadow.position.is_zero_approx())
	assert(boss.shadow.scale.y < boss.shadow.scale.x, "Ground shadow must be flat")
	boss.skybreaker_finished.connect(func(): skybreaker_count += 1)
	boss.area_damage_requested.connect(func(_p, _r, _d): area_count += 1)
	boss.melee_damage_requested.connect(func(_p, _r, _d): melee_count += 1)
	player.damage_received.connect(func(_amount): player_hit_count += 1)

	assert(boss.state == boss.State.SITTING)
	assert(boss.get_node("Back").visible and boss.get_node("Seat").visible, "Chair layers must remain visible from the first frame")
	press_space()
	await physics_frame
	assert(boss.state == boss.State.SITTING, "Space cannot skip the throne introduction")
	await arena.entrance_finished

	# Move until the throne enters the camera; the encounter must take control.
	player.position = Vector2(0, -112)
	player.reset_physics_interpolation()
	camera.reset_smoothing()
	for frame in range(180):
		await physics_frame
		if boss.state != boss.State.SITTING:
			break
	assert(boss.state == boss.State.PLAYER_APPROACH, "Visible throne must trigger the approach")
	assert(player.intro_locked, "Player control must be locked during the approach")

	for frame in range(240):
		await physics_frame
		if boss.state == boss.State.THRONE_PAUSE:
			break
	assert(boss.state == boss.State.THRONE_PAUSE)
	assert(player.position.distance_to(Vector2(0, -192)) < 0.1)
	await capture("seated_layered")
	var pause_start := Engine.get_physics_frames()
	for frame in range(150):
		assert(player.intro_locked, "Control must remain locked during the pause")
		assert(boss.get_node("Asterion").visible, "Asterion must remain seated during the pause")
		assert(boss.get_node("Back").visible and boss.get_node("Seat").visible, "Chair cannot flicker during the pause")
		assert(not boss.actor.visible)
		assert(player.position.distance_to(Vector2(0, -192)) < 0.1)
		await physics_frame
		if boss.state == boss.State.THRONE_STANDING:
			break
	assert(boss.state == boss.State.THRONE_STANDING)
	assert(absi(Engine.get_physics_frames() - pause_start - 120) <= 1, "Pause must last two seconds at 60 Hz")
	assert(player.position.distance_to(boss.intro_destination) < 0.1)
	assert(not boss.get_node("Asterion").visible)
	assert(boss.get_node("Back").visible and boss.get_node("Seat").visible)
	await capture("standing_transition")

	var released_during_launch := false
	for frame in range(420):
		await physics_frame
		assert(boss.actor.z_index < arena.get_node("Chain1").z_index + arena.get_node("Chain1/Sprite").z_index, "Chains must stay in front during the jump")
		if boss.state == boss.State.LAUNCHING:
			assert(not boss.field_skybreaker_visual.visible, "Throne launch keeps its original propulsion visual")
		if boss.state == boss.State.OFFSCREEN and not player.intro_locked:
			released_during_launch = true
		if skybreaker_count == 1:
			break
	assert(released_during_launch, "Control must return while Asterion is airborne")
	assert(skybreaker_count == 1 and area_count == 1)
	assert(boss.actor.visible and boss.get_node("Actor/GroundShadow").visible)
	assert(not boss.get_node("Asterion").visible, "Asterion must not return to the chair")

	# Give Asterion room to display the walk cycle and pursuit.
	player.global_position = boss.actor.global_position + Vector2(0, 75)
	player.reset_physics_interpolation()
	camera.reset_smoothing()
	var chase_start: Vector2 = boss.actor.global_position
	for frame in range(45):
		await physics_frame
	assert(boss.actor.global_position.distance_to(player.global_position) < chase_start.distance_to(player.global_position))
	assert(boss.visual.texture in boss.WALK_FRAMES, "Chase must use the walk sequence")
	await capture("walk")

	# Close range must display prepare, attack and one damage event.
	player.global_position = boss.actor.global_position + Vector2(27, 0)
	player.reset_physics_interpolation()
	var saw_prepare := false
	var saw_attack := false
	for frame in range(180):
		await physics_frame
		saw_prepare = saw_prepare or boss.state == boss.State.MELEE_PREPARE
		saw_attack = saw_attack or boss.state == boss.State.MELEE_ATTACK
		if melee_count > 0:
			break
	assert(saw_prepare and saw_attack and melee_count == 1)
	await capture("melee")

	# Move away, then Space starts another Skybreaker from the arena floor.
	player.global_position = boss.actor.global_position + Vector2(0, 80)
	player.reset_physics_interpolation()
	for frame in range(120):
		await physics_frame
		if boss.state == boss.State.CHASE:
			break
	assert(boss.state == boss.State.CHASE)
	press_space()
	await physics_frame
	assert(boss.state == boss.State.SKYBREAKER_PREPARE, "Space must start the field Skybreaker")
	assert(boss.visual.texture in boss.SKYBREAKER_PREPARE_FRAMES)
	for frame in range(30):
		await physics_frame
		if boss.state == boss.State.LAUNCHING:
			break
	assert(boss.state == boss.State.LAUNCHING)
	assert(boss.field_skybreaker_visual.visible and not boss.visual.visible)
	assert(boss.field_skybreaker_visual.texture == boss.SKYBREAKER_PREPARE_FRAMES[2], "Field launch must keep prepare3")
	await capture("field_launch")

	for frame in range(480):
		await physics_frame
		if skybreaker_count == 2:
			break
	assert(skybreaker_count == 2 and area_count == 2, "Every jump must produce one impact")
	assert(not boss.get_node("Asterion").visible, "The chair remains empty after repeated jumps")
	assert(camera.offset.is_zero_approx() and is_zero_approx(camera.rotation))
	print("ASTERION_ENCOUNTER_CHECKS_OK skybreakers=", skybreaker_count, " melee=", melee_count, " player_hits=", player_hit_count)
	quit()
