extends SceneTree
## Real map, real projectile damage, physics, progression and E-to-fresh-game regression.
const ARENA: PackedScene = preload("res://scenes/dungeon/ldtk_arena.tscn")
const GHOST: Script = preload("res://scripts/enemies/spirit_ghost.gd")
const PROJECTILE: PackedScene = preload("res://scenes/dungeon/manifestation_projectile.tscn")
var failures: Array[String] = []
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func wait_entry(arena: Node2D) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while is_instance_valid(arena) and not bool(arena.get("entry_complete")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(is_instance_valid(arena) and bool(arena.get("entry_complete")), "Entry cutscene must finish")


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/spirit_horde"))
	check(root.get_texture().get_image().save_png("res://output/spirit_horde/" + label + ".png") == OK, "Capture saves")


func key_e(pressed: bool) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	key.pressed = pressed
	Input.parse_input_event(key)


func move_key(pressed: bool) -> void:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	key.pressed = pressed
	Input.parse_input_event(key)


func clear_actors(horde: Node2D) -> void:
	for actor: Node2D in (horde.get("actors") as Array).duplicate():
		actor.call("dismiss")


func shoot(arena: Node2D, enemy: Node2D) -> void:
	var player: Player = arena.get_node("Nox") as Player
	var shooter: Node = player.get_node("BoosterShooter")
	var attack: CardAttack = (shooter.get("card_runtime") as CardCombatRuntime).create_attack()
	var projectile: Node2D = PROJECTILE.instantiate() as Node2D
	arena.get_node("PlayerProjectiles").add_child(projectile)
	projectile.global_position = enemy.global_position + Vector2(-48, -7)
	projectile.call("configure", &"M01", Vector2.RIGHT, attack, shooter.get("effects"), player)
	projectile.reset_physics_interpolation()
	await ticks(16)


func _run() -> void:
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	var arena: Node2D = ARENA.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	await wait_entry(arena)
	var player: Player = arena.get_node("Nox") as Player
	var life_bar: Range = arena.get_node("PlayerHUD/Interface/SafeArea/Column/HP") as Range
	check(life_bar.value == player.health and life_bar.max_value == player.max_health, "Room_1 shows the authored player life meter")
	player.receive_skybreaker_hit(12.0)
	check(life_bar.value == player.health and life_bar.value == player.max_health - 12.0, "Room_1 life meter follows actual damage")
	player.heal_full()
	check(life_bar.value == player.max_health, "Room_1 life meter follows healing")
	var gameplay: Node2D = arena.get_node("Gameplay") as Node2D
	var hordes: Array = arena.get_node("SpiritHordes").get("encounters") as Array
	check(hordes.size() == 1, "Authored Room_1 creates one spirit encounter")
	if hordes.is_empty():
		quit(1)
		return
	var horde: Node2D = hordes[0] as Node2D
	check(int(horde.get("kill_target")) == 40, "Spawn reduction must retain the forty-kill objective")
	check(is_equal_approx(float((horde.get("profile") as Resource).get("spawn_interval")), 0.4 / 0.75), "Spawn interval gives twenty-five percent fewer emissions than the previous 0.4 seconds")
	var gates: Array = arena.get_node("Warps").get("gates") as Array
	var exit_gate: Node2D = gates[1] as Node2D
	check(player.position.is_equal_approx(Vector2(264, 808)), "Game starts at original entry warp / Start")
	check(not bool(gameplay.call("is_door_cell_locked", Vector2i(28, 58))), "Entry door is open before encounter")
	check(bool(gameplay.call("is_door_cell_locked", Vector2i(52, 43))), "Exit door starts closed")
	check(int(horde.get("phase")) == 0 and (horde.get("actors") as Array).is_empty(), "No horde before entering the chamber")
	check(not bool(exit_gate.call("can_travel")), "Exit cannot travel before 40 combat kills")
	check(not (exit_gate.get_node("WhiteCirculation") as Node2D).visible, "White circulation waits for clear")
	var dummy: Node2D = GHOST.new() as Node2D
	dummy.position = Vector2(650, 760)
	arena.add_child(dummy)
	check(float(dummy.call("get_current_health")) == 3.0, "Spirit health is one three-point unit")
	await shoot(arena, dummy)
	check(not is_instance_valid(dummy) or not bool(dummy.call("is_alive")), "One real M01 hit kills the three-HP spirit")
	check(int(horde.get("defeated_count")) == 0, "Unrelated enemies do not count toward this room encounter")
	player.position = Vector2(650, 710)
	player.reset_physics_interpolation()
	await ticks(2)
	check(int(horde.get("phase")) == 0, "Entering painted chamber waits for the pedestal")
	var pedestal: Node2D = (arena.get_node("HordePedestals").get("pedestals") as Array)[0] as Node2D
	player.position = pedestal.position - Vector2(0, 3)
	player.snap_floor_height()
	await ticks(2)
	key_e(true)
	await ticks(2)
	key_e(false)
	check(int(horde.get("phase")) == 1, "E on the elevated pedestal begins the horde")
	check(bool(gameplay.call("is_door_cell_locked", Vector2i(28, 58))), "Entry seals after the player crosses it")
	check((horde.get("actors") as Array).size() >= 12, "Horde begins with a sizeable pack")
	var sides: Dictionary = {}
	for actor: Node2D in horde.get("actors") as Array:
		var view: Rect2 = actor.get_meta("spawn_viewport") as Rect2
		var origin: Vector2 = actor.get_meta("spawn_position") as Vector2
		check(not view.has_point(origin), "Every spirit is born offscreen")
		check(not bool(arena.call("is_sword_ground_point", horde.to_global(origin))), "Every spirit is born outside painted floor")
		sides[int(actor.get_meta("spawn_side"))] = true
		check((actor as CharacterBody2D).collision_mask == 4, "Spirits ignore all terrain, borders and closed doors")
	check(sides.size() == 4, "Initial pack surrounds the viewport from all four directions")
	horde.set("_spawn_remaining", 999.0)
	clear_actors(horde)
	# Wall penetration with real Godot movement physics and live encounter steering.
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(650, 690)
	var collider: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(100, 10)
	collider.shape = shape
	wall.add_child(collider)
	arena.add_child(wall)
	player.position = Vector2(650, 650)
	horde.set("_previous_player", player.position)
	var phaser: Node2D = horde.call("_spawn_one") as Node2D
	phaser.position = Vector2(650, 722)
	phaser.reset_physics_interpolation()
	await ticks(55)
	check(phaser.position.y < 685, "Spirit crosses a solid wall instead of navigating around it")
	wall.queue_free()
	# The contact disappearance must neither count as a kill nor bypass invulnerability.
	player.health = player.max_health
	player.contact_invulnerability = 0.0
	phaser.position = player.position + Vector2(8, 3)
	phaser.reset_physics_interpolation()
	await ticks(2)
	check(player.health == player.max_health - 3.0, "Stage zero contact applies exactly 3 damage")
	check(not bool(phaser.call("is_alive")), "Contact consumes the spirit")
	check(int(horde.get("defeated_count")) == 0, "Contact disappearance does not unlock the door")
	check(is_equal_approx(player.contact_slow_factor, 0.55) and player.contact_slow_remaining > 0.40, "Successful hit briefly slows movement by 45 percent")
	check(player.contact_invulnerability > 1.0, "Contact protection includes slow duration plus the post-slow window")
	player.position = Vector2(650, 730)
	horde.set("_previous_player", player.position)
	player.knockback_velocity = Vector2.ZERO
	player.impact_control_lock = 0.0
	var motion_start: Vector2 = player.position
	move_key(true)
	await ticks(12)
	move_key(false)
	var slowed_distance: float = player.position.distance_to(motion_start)
	check(slowed_distance > 8.0 and slowed_distance < 12.0, "Slow changes actual walking distance, independently of card modifiers")
	await ticks(18)
	check(player.contact_slow_remaining == 0.0 and player.contact_slow_factor == 1.0, "Normal movement recovers when slow ends")
	check(player.contact_invulnerability > 0.45, "Player remains invulnerable after the slow ends")
	var protected_health: float = player.health
	player.receive_contact_damage(3)
	check(player.health == protected_health, "Post-slow protection prevents another contact hit")
	await ticks(38)
	player.receive_contact_damage(3)
	check(player.health == protected_health - 3.0, "Contact damage resumes once post-slow protection expires")
	clear_actors(horde)
	player.position = Vector2(780, 710)
	horde.set("_previous_player", player.position)
	player.contact_invulnerability = 100.0
	player.reset_physics_interpolation()
	for index: int in range(30):
		var actor: Node2D = horde.call("_spawn_one") as Node2D
		actor.position = Vector2(580 + (index % 6) * 17, 750 + int(index / 6.0) * 17)
		actor.reset_physics_interpolation()
	await ticks(70)
	var minimum: float = INF
	var crowd: Array = horde.get("actors") as Array
	for first: int in range(crowd.size()):
		for second: int in range(first + 1, crowd.size()):
			minimum = minf(minimum, (crowd[first] as Node2D).position.distance_to((crowd[second] as Node2D).position))
	check(minimum >= 13.8, "Crowd bodies prevent complete overlap (14px minimum separation)")
	check(crowd.size() <= 36, "Horde has a bounded active crowd")
	await capture("horde")
	for count: int in range(1, 41):
		var remaining: Array = horde.get("actors") as Array
		var victim: Node2D = remaining[0] as Node2D if not remaining.is_empty() else horde.call("_spawn_one") as Node2D
		victim.call("take_damage", 12.0)
		check(int(horde.get("defeated_count")) == count, "Combat kill counted once at %d" % count)
		if count in [10, 20, 30]:
			var stage: int = int(count / 10.0)
			check(int(horde.get("difficulty_stage")) == stage, "Buff applies at %d kills" % count)
			var survivor: Node2D = horde.call("_spawn_one") as Node2D
			check(float(survivor.get("movement_speed")) == 48.0 + stage * 12.0, "Stage speed grows")
			check(int(survivor.get("contact_damage")) == (stage + 1) * 3, "Stage damage follows base three")
			check(float(survivor.get("sway_strength")) > 0.0 and float(survivor.get("resistance")) == 3.0, "Movement changes while three-point health remains fixed")
	check(int(horde.get("phase")) == 2 and (horde.get("actors") as Array).is_empty(), "Forty kills end spawning and dismiss the remaining horde")
	check(not bool(gameplay.call("is_door_cell_locked", Vector2i(52, 43))), "Forty kills open the exit")
	await ticks(2)
	check((exit_gate.get_node("WhiteCirculation") as Node2D).visible, "Cleared portal displays white circulation")
	player.position = exit_gate.call("spawn_position") as Vector2
	player.reset_physics_interpolation()
	await ticks(5)
	check(not bool(arena.get("_travel_busy")), "Exit waits for E instead of automatically teleporting")
	await capture("exit_ready")
	player.health = 30.0
	player.dash_charges = 0
	player.dash_recovery = 0.4
	var old_runtime: CardCombatRuntime = player.get_node("BoosterShooter").get("card_runtime") as CardCombatRuntime
	old_runtime.mutation_remaining = 5.0
	key_e(true)
	await ticks(2)
	key_e(false)
	check(player.intro_locked and bool(arena.get("_travel_busy")), "E starts the existing beam and fade")
	var deadline: int = Time.get_ticks_msec() + 5000
	while is_instance_valid(arena) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not is_instance_valid(arena), "Exit destroys the completed room")
	var fresh: Node2D = current_scene as Node2D
	if is_instance_valid(fresh):
		check(fresh.scene_file_path == "res://scenes/tutorial_arena.tscn", "Room_1 exit leads to Asterion")
		var fresh_player: Player = fresh.get_node("Mox") as Player
		check(fresh_player.health == 30.0 and fresh_player.position.is_equal_approx(Vector2(0, 204)), "Travel preserves health at the authored Asterion arrival")
		var fresh_runtime: CardCombatRuntime = fresh_player.get_node("BoosterShooter").get("card_runtime") as CardCombatRuntime
		check(fresh_runtime == old_runtime, "Travel preserves equipped cards and effects")
		fresh.queue_free()
	await ticks(3)
	print("SPIRIT_HORDE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " | minimum spacing=", minimum, " | failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
