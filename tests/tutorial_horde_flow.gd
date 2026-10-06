extends Node
const ARENA: PackedScene = preload("res://scenes/tutorial_arena.tscn")
const BOSS: Script = preload("res://scripts/asterion_skybreaker.gd")
var failures: int = 0
var jumps: int = 0
var reinforcements: int = 0
var hits_on_player: int = 0
var spawns_after_end: int = 0
var stopped: bool = false
var encounter: Variant
var player: Player
var horde: Variant
var weapon: Variant
var boss: Variant
var shots: int = 0
var capture_enabled: bool = false
var initial_mouse: Vector2i

func _ready() -> void:
	capture_enabled = DisplayServer.get_name() != "headless"
	if capture_enabled: initial_mouse = DisplayServer.mouse_get_position()
	var arena: Node2D = ARENA.instantiate() as Node2D
	boss = arena.get_node("MinotaurChair")
	boss.skybreaker_started.connect(func() -> void: jumps += 1)
	add_child(arena)
	player = arena.get_node("Mox") as Player
	player.damage_received.connect(func(_amount: float) -> void: hits_on_player += 1)
	weapon = player.get_node("BoosterShooter")
	weapon.shot_fired.connect(func() -> void: shots += 1)
	encounter = boss.get_node("TutorialEncounter")
	horde = encounter.get_node("Horde")
	horde.enemy_spawned.connect(_check_spawn)
	horde.spawning_finished.connect(func() -> void: stopped = true)
	var box: DialogueBox = boss.get_node("IntroDialogue") as DialogueBox
	for tick: int in range(500):
		await get_tree().physics_frame
		if bool(arena.get("entrance_complete")): break
	_check(not weapon.equipped and not weapon.visible, "Weapon hidden during arrival/exploration")
	_key(KEY_W, true)
	for tick: int in range(600):
		await get_tree().physics_frame
		if box.is_dialogue_active(): break
	_key(KEY_W, false)
	_check(box.is_dialogue_active(), "First encounter starts")
	for index: int in range(8):
		_check(box.current_line_index() == index, "First conversation order")
		await _advance(box)
	_check(not box.is_dialogue_active() and weapon.equipped and weapon.visible, "Threat hides dialogue and reveals weapon")
	_check(player.intro_locked and not weapon.combat_enabled, "Reveal cannot fire or move")
	await _capture("reveal")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	_check(jumps == 0, "Space cannot bypass minion encounter")
	for tick: int in range(160):
		await get_tree().physics_frame
		if box.is_dialogue_active(): break
	_check(box.is_dialogue_active(), "Dialogue resumes after reveal")
	box.reveal_current_line()
	await get_tree().process_frame
	_check(box.body_text.get_content_height() <= box.body_text.size.y + 1.0, "Threat response fits dialogue panel")
	await _capture("threat")
	await _advance(box)
	await _advance(box)
	for tick: int in range(4):
		await get_tree().physics_frame
	_check(not box.is_dialogue_active() and player.intro_locked, "Call starts the staged entrance with control locked")
	_check(encounter.phase == encounter.Phase.OPENING and not weapon.combat_enabled, "Combat waits for the opening wave")
	_check(weapon.cutscene_pose_active, "Weapon transitions to its dialogue pose during the staged entrance")
	_check(horde.initial_count >= 8, "Opening creates several minotaurs at the map bottom")
	var opening_view: Rect2 = horde.visible_world_rect()
	for enemy: Minotaur in horde.alive:
		_check(enemy.global_position.y > opening_view.end.y, "Every opening minotaur starts below the screen")
	_check(jumps == 0 and boss.get_node("Asterion").visible, "Boss stays decorative and seated")
	await _capture("entry_start")
	for tick: int in range(420):
		await get_tree().physics_frame
		if encounter.phase == encounter.Phase.HORDE:
			break
	_check(encounter.phase == encounter.Phase.HORDE and not player.intro_locked, "Phase starts only after the wave enters the lower screen")
	_check(weapon.combat_enabled and not weapon.cutscene_pose_active, "Combat enables aim and fire after the entrance")
	_check(horde.elapsed < 0.1, "Spawn timer begins after the entrance")
	await _capture("opening")
	# Do not shoot: verify full spawn duration, population cap and no timer-only clear.
	for tick: int in range(2300):
		await get_tree().physics_frame
		_check(horde.alive.size() <= horde.maximum_alive, "Population cap")
		if not horde.spawning: break
	_check(stopped and horde.elapsed >= 35.0 and horde.elapsed < 35.2, "35 seconds of spawning")
	_check(reinforcements > 0, "Reinforcements spawn outside screen")
	_check(encounter.phase == encounter.Phase.HORDE and horde.alive.size() > 0, "Timer alone does not finish horde")
	_check(hits_on_player > 0, "Minotaurs attack and hit Nox")
	_check(jumps == 0, "Asterion never attacks during hordes")
	await _capture("combat")
	# Aim using mouse input and defeat the actual minions with the restored projectiles.
	_mouse_button(true)
	for tick: int in range(1200):
		if not horde.active: break
		var nearest: Minotaur = null
		var distance: float = INF
		for enemy: Minotaur in horde.alive:
			var candidate_distance: float = player.global_position.distance_squared_to(enemy.global_position)
			if candidate_distance < distance:
				nearest = enemy
				distance = candidate_distance
		if is_instance_valid(nearest):
			_aim(nearest.global_position)
		await get_tree().physics_frame
	_mouse_button(false)
	_check(not horde.active and horde.alive.is_empty(), "Real bullets can defeat every remaining minotaur")
	_check(shots > 0 and horde.total_killed == horde.total_spawned, "Every spawned enemy is accounted for")
	_check(spawns_after_end == 0, "No spawns after timer")
	_check(box.is_dialogue_active(), "Asterion roars when the final minotaur dies")
	_check("GRRRAAAAH" in box.body_text.get_parsed_text(), "The final counter is replaced by Asterion's roar")
	_check(not encounter.hint.visible, "No remaining-minotaur counter is shown")
	await _capture("roar")
	_check(weapon.cutscene_pose_active and not weapon.combat_enabled, "Weapon returns to its side pose after combat")
	_check(jumps == 0, "Boss waits for Nox to approach")
	for tick: int in range(350):
		await get_tree().physics_frame
		if box.is_dialogue_active() and "Quer saber" in box.body_text.get_parsed_text():
			break
	_check(box.is_dialogue_active() and "Quer saber" in box.body_text.get_parsed_text(), "Approach starts the final conversation")
	await _advance(box)
	_check(jumps == 1, "Challenge starts first jump")
	for tick: int in range(450):
		await get_tree().physics_frame
		if int(boss.state) == BOSS.State.CHASE: break
	_check(int(boss.state) == BOSS.State.CHASE, "Boss lands and enters existing combat")
	await _tap(KEY_SPACE)
	_check(jumps == 2, "Space still triggers field jump")
	print("[HORDE FLOW] failures=%d initial=%d reinforcements=%d spawned=%d killed=%d shots=%d hits=%d jumps=%d duration=%.2f" % [failures,horde.initial_count,reinforcements,horde.total_spawned,horde.total_killed,shots,hits_on_player,jumps,horde.elapsed])
	if capture_enabled: DisplayServer.warp_mouse(initial_mouse)
	get_tree().quit(0 if failures == 0 else 1)

func _check_spawn(enemy: Minotaur) -> void:
	if stopped: spawns_after_end += 1
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 11.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, enemy.global_position)
	query.collision_mask = 1
	_check(enemy.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(), "Spawn avoids craters and throne")
	if not horde.last_spawn_was_opening:
		reinforcements += 1
		_check(not horde.visible_world_rect().grow(20.0).has_point(enemy.global_position), "Every reinforcement starts outside screen")

func _advance(box: DialogueBox) -> void:
	if box.is_revealing_text(): await _tap(KEY_E)
	await _tap(KEY_E)

func _tap(code: Key) -> void:
	_key(code,true)
	await get_tree().process_frame
	_key(code,false)
	await get_tree().process_frame

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _mouse_button(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _aim(point: Vector2) -> void:
	if capture_enabled:
		get_viewport().warp_mouse(get_viewport().get_canvas_transform() * point)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = get_viewport().get_final_transform() * get_viewport().get_canvas_transform() * point
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _capture(label: String) -> void:
	if not capture_enabled: return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tmp/horde_" + label + ".png")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("[HORDE FLOW] " + message)









