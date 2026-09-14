extends StaticBody2D
## Visual encounter controller: throne intro, Skybreaker, chase and melee loop.

signal encounter_started
signal skybreaker_started
signal launch_left_camera
signal target_locked(position: Vector2)
signal impact_started(position: Vector2)
signal area_damage_requested(position: Vector2, radius: float, damage: float)
signal melee_started
signal melee_damage_requested(position: Vector2, radius: float, damage: float)
signal skybreaker_finished

@export_category("Combat balance")
@export var max_resistance: float = 90.0
enum State {
	SITTING,
	PLAYER_APPROACH,
	THRONE_PAUSE,
	THRONE_STANDING,
	THRONE_PROPULSION,
	SKYBREAKER_PREPARE,
	LAUNCHING,
	OFFSCREEN,
	DESCENDING,
	HIT_1,
	HIT_2,
	RECOVERY,
	CHASE,
	MELEE_PREPARE,
	MELEE_ATTACK,
	MELEE_RECOVERY,
	INTRO_DIALOGUE,
	WEAPON_REVEAL,
	HORDE,
	WAIT_RETURN,
}

const STANDING = preload("res://assets/enemies/minotaur/elite/animation/propulsion/standing.png")
const PROPULSION = preload("res://assets/enemies/minotaur/elite/animation/propulsion/propulsion.png")
const LAUNCH = preload("res://assets/enemies/minotaur/elite/animation/propulsion/propulsion_fly.png")
const FLYING = preload("res://assets/enemies/minotaur/elite/animation/skybreaker/flying_redimensioned.png")
const HIT_1_TEXTURE = preload("res://assets/enemies/minotaur/elite/animation/skybreaker/hit1_redimensioned.png")
const HIT_2_TEXTURE = preload("res://assets/enemies/minotaur/elite/animation/skybreaker/hit2_redimensioned.png")
const SKYBREAKER_PREPARE_FRAMES = [
	preload("res://assets/enemies/minotaur/elite/skybreaker_jump/prepare1.png"),
	preload("res://assets/enemies/minotaur/elite/skybreaker_jump/prepare2.png"),
	preload("res://assets/enemies/minotaur/elite/skybreaker_jump/prepare3.png"),
]
const WALK_FRAMES = [
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk1.png"),
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk2.png"),
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk3.png"),
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk4.png"),
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk5.png"),
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk6.png"),
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk7.png"),
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk8.png"),
	preload("res://assets/enemies/minotaur/elite/walk/minotaur_elite_walk9.png"),
]
const MELEE_PREPARE_FRAMES = [
	preload("res://assets/enemies/minotaur/elite/attack/prepare/prepare1.png"),
	preload("res://assets/enemies/minotaur/elite/attack/prepare/prepare2.png"),
	preload("res://assets/enemies/minotaur/elite/attack/prepare/prepare3.png"),
]
const MELEE_ATTACK_FRAMES = [
	preload("res://assets/enemies/minotaur/elite/attack/attack/attack1.png"),
	preload("res://assets/enemies/minotaur/elite/attack/attack/attack2.png"),
	preload("res://assets/enemies/minotaur/elite/attack/attack/attack3.png"),
	preload("res://assets/enemies/minotaur/elite/attack/attack/attack4.png"),
	preload("res://assets/enemies/minotaur/elite/attack/attack/attack5.png"),
]

const THRONE_STANDING_DURATION := 0.50
const THRONE_PROPULSION_DURATION := 0.18
const PREPARE_FRAME_DURATION := 0.12
const LAUNCH_DURATION := 0.45
const OFFSCREEN_DURATION := 2.0
const TARGET_LOCK_TIME := 1.25
const DESCENT_DURATION := 0.65
const HIT_1_DURATION := 0.12
const HIT_2_DURATION := 0.18
const RECOVERY_DURATION := 0.30
const WALK_FRAME_DURATION := 0.09
const ATTACK_FRAME_DURATION := 0.10
const MELEE_RECOVERY_DURATION := 0.45
const LARGE_FRAME_FOOT := Vector2(64, 93)
const FLYING_FRAME_FOOT := Vector2(64, 96)
const HIT_1_FRAME_FOOT := Vector2(63, 96)
const HIT_2_FRAME_FOOT := Vector2(57, 96)
# Anchors follow the body, not the axe, impact effect or transparent canvas.
const WALK_FOOT_X := [25.0, 28.0, 28.0, 25.0, 24.0, 23.0, 26.0, 26.0, 25.0]
const ATTACK_FOOT_X := [37.0, 40.0, 24.0, 24.0, 24.0]
const GROUND_FOOT_Y := 48.0
const ACTOR_DRAW_LAYER := 2

@export var intro_dialogue: DialogueSequence = preload("res://resources/dialogue/asterion_intro.tres")

@export var intro_destination := Vector2(0, -192)
@export var intro_pause_duration := 2.0
@export var intro_walk_speed := 82.0
@export var auto_start_encounter := true
@export var chase_speed := 44.0
@export var melee_range := 32.0
@export var melee_hit_range := 38.0
@export var melee_damage := 1.0
@export var impact_radius := 40.0
@export var preview_damage := 1.0
@export var melee_decision_cooldown := 0.75
@export var skybreaker_decision_cooldown := 3.5
@export_range(0.0, 1.0) var shake_intensity := 1.0

var state: State = State.SITTING
var state_time := 0.0
var elapsed := 0.0
var impact_position := Vector2.ZERO
var target_is_locked := false
var damage_emitted := false
var melee_damage_emitted := false
var launch_position := Vector2.ZERO
var descent_position := Vector2.ZERO
var intro_started := false
var facing_left := false
var shake_time := 0.0
var shake_duration := 0.0
var shake_pixels := 0.0
var shake_angle := 0.0
var camera_offset := Vector2.ZERO
var camera_rotation := 0.0
var camera_ignore_rotation := true
var _sense_left: float = 0.0
var _observation: EnemyAIObservation
var _decision: EnemyAIDecision

@onready var tutorial_encounter: Node = $TutorialEncounter
@onready var dialogue_box: DialogueBox = $IntroDialogue
@onready var arena: Node2D = get_parent()
@onready var actor: CharacterBody2D = $Actor
@onready var visual: Sprite2D = $Actor/Visual
@onready var field_skybreaker_visual: Sprite2D = $Actor/FieldSkybreakerVisual
@onready var body_shape: CollisionShape2D = $Actor/BodyCollision
@onready var shadow: Node2D = $Actor/GroundShadow
@onready var effect: Node2D = $ImpactEffect
@onready var ai: AsterionAI = $AI
@onready var ai_world_sensor: EnemyAIWorldSensor2D = $AIWorldSensor
@onready var player: CharacterBody2D = arena.get_node("Mox")
@onready var camera: Camera2D = player.get_node("Camera2D")


func _ready() -> void:
	dialogue_box.dialogue_finished.connect(_on_intro_dialogue_finished)
	tutorial_encounter.setup(self, arena, player, dialogue_box)
	ai_world_sensor.configure(arena, Rect2(arena.to_global(player.arena_bounds.position), player.arena_bounds.size * arena.global_scale))
	actor.add_to_group(&"enemy_ai_actor")
	actor.set_meta(&"enemy_ai_is_elite", true)
	ai.elite_profile.attack_range = maxf(melee_range - ai_world_sensor.attack_slot_radius, 1.0)
	ai.elite_profile.preferred_distance = melee_range
	ai.elite_profile.attack_cooldown = melee_decision_cooldown
	ai.elite_profile.special_cooldown = skybreaker_decision_cooldown
	ai.skybreaker_min_distance = maxf(ai.skybreaker_min_distance, melee_range * 2.0)
	ai.elite_profile.special_min_distance = ai.skybreaker_min_distance


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_SPACE or event.keycode == KEY_SPACE):
		if start_skybreaker():
			get_viewport().set_input_as_handled()


func start_skybreaker() -> bool:
	if state not in [State.CHASE, State.MELEE_PREPARE, State.MELEE_ATTACK, State.MELEE_RECOVERY]:
		return false
	_capture_camera()
	elapsed = 0.0
	target_is_locked = false
	damage_emitted = false
	impact_position = Vector2.ZERO
	actor.velocity = Vector2.ZERO
	_set_ground_pose(SKYBREAKER_PREPARE_FRAMES[0])
	_enter(State.SKYBREAKER_PREPARE)
	skybreaker_started.emit()
	return true


func _physics_process(delta: float) -> void:
	_update_shake(delta)
	match state:
		State.SITTING:
			if auto_start_encounter and not intro_started and arena.entrance_complete and _throne_is_visible():
				_begin_player_approach()
		State.PLAYER_APPROACH:
			_update_player_approach(delta)
		State.THRONE_PAUSE:
			_tick_timed_state(delta, intro_pause_duration, _begin_intro_dialogue)
		State.THRONE_STANDING:
			_tick_timed_state(delta, THRONE_STANDING_DURATION, _finish_throne_standing)
		State.THRONE_PROPULSION:
			_tick_timed_state(delta, THRONE_PROPULSION_DURATION, _finish_throne_propulsion)
		State.SKYBREAKER_PREPARE:
			_update_skybreaker_prepare(delta)
		State.LAUNCHING:
			_update_launch(delta)
		State.OFFSCREEN:
			_update_offscreen(delta)
		State.DESCENDING:
			_update_descent(delta)
		State.HIT_1:
			_tick_timed_state(delta, HIT_1_DURATION, _finish_hit_1)
		State.HIT_2:
			_tick_timed_state(delta, HIT_2_DURATION, _finish_hit_2)
		State.RECOVERY:
			_tick_timed_state(delta, RECOVERY_DURATION, _finish_skybreaker)
		State.CHASE:
			_update_chase(delta)
		State.MELEE_PREPARE:
			_update_melee_prepare(delta)
		State.MELEE_ATTACK:
			_update_melee_attack(delta)
		State.MELEE_RECOVERY:
			_tick_timed_state(delta, MELEE_RECOVERY_DURATION, _finish_melee_recovery)


func _begin_player_approach() -> void:
	intro_started = true
	player.intro_locked = true
	player.velocity = Vector2.ZERO
	player.body.play(&"run")
	player.body.flip_h = intro_destination.x < player.position.x
	_enter(State.PLAYER_APPROACH)
	encounter_started.emit()


func _update_player_approach(delta: float) -> void:
	var destination := arena.to_global(intro_destination)
	var distance := player.global_position.distance_to(destination)
	if distance <= intro_walk_speed * delta:
		player.global_position = destination
		player.velocity = Vector2.ZERO
		player.body.play(&"idle")
		_enter(State.THRONE_PAUSE)
		return
	player.global_position = player.global_position.move_toward(destination, intro_walk_speed * delta)


func _begin_intro_dialogue() -> void:
	# Keep the seated idle and the existing player lock until the first takeoff.
	_enter(State.INTRO_DIALOGUE)
	player.velocity = Vector2.ZERO
	player.body.play(&"idle")
	tutorial_encounter.begin_dialogue()


func _on_intro_dialogue_finished(sequence_id: StringName) -> void:
	if state != State.INTRO_DIALOGUE:
		return
	tutorial_encounter.on_dialogue_finished(sequence_id)


func _start_from_throne() -> void:
	_capture_camera()
	elapsed = 0.0
	target_is_locked = false
	damage_emitted = false
	impact_position = Vector2.ZERO
	# Keep the same canvas, transform and throne ordering through both anticipation poses.
	$Asterion.play(&"standing")
	actor.hide()
	shadow.hide()
	_enter(State.THRONE_STANDING)
	skybreaker_started.emit()


func _finish_throne_standing() -> void:
	$Asterion.play(&"propulsion")
	_enter(State.THRONE_PROPULSION)


func _finish_throne_propulsion() -> void:
	$Asterion.hide()
	actor.global_position = $LaunchOrigin.global_position
	_set_pose(LAUNCH, LARGE_FRAME_FOOT)
	actor.reset_physics_interpolation()
	actor.show()
	_begin_launch()


func _update_skybreaker_prepare(delta: float) -> void:
	state_time += delta
	elapsed += delta
	var frame := mini(int(state_time / PREPARE_FRAME_DURATION), SKYBREAKER_PREPARE_FRAMES.size() - 1)
	_set_ground_pose(SKYBREAKER_PREPARE_FRAMES[frame])
	if state_time >= PREPARE_FRAME_DURATION * SKYBREAKER_PREPARE_FRAMES.size():
		_show_field_skybreaker_launch()
		_begin_launch()


func _begin_launch() -> void:
	ai.notify_special_attack_committed(skybreaker_decision_cooldown)
	ai.notify_attack_committed(RECOVERY_DURATION)
	launch_position = actor.global_position
	actor.velocity = Vector2.ZERO
	# Chains hang in front of the arena and must also occlude the airborne boss.
	actor.z_index = ACTOR_DRAW_LAYER
	body_shape.set_deferred("disabled", true)
	shadow.hide()
	_shake(6.0, 2.5, 0.45)
	_enter(State.LAUNCHING)


func _update_launch(delta: float) -> void:
	state_time += delta
	elapsed += delta
	var t := clampf(state_time / LAUNCH_DURATION, 0.0, 1.0)
	var end_y := minf(launch_position.y - 180.0, _camera_top() - 80.0)
	actor.global_position = launch_position.lerp(Vector2(launch_position.x, end_y), 1.0 - pow(1.0 - t, 2.0))
	if state_time >= LAUNCH_DURATION:
		actor.hide()
		_set_pose(FLYING, FLYING_FRAME_FOOT)
		if player.intro_locked:
			player.intro_locked = false
			player.body.play(&"idle")
		_enter(State.OFFSCREEN)
		launch_left_camera.emit()


func _update_offscreen(delta: float) -> void:
	state_time += delta
	elapsed += delta
	if not target_is_locked and state_time >= TARGET_LOCK_TIME:
		impact_position = _safe_landing(player.global_position + Vector2(0, 7))
		target_is_locked = true
		target_locked.emit(impact_position)
	if state_time >= OFFSCREEN_DURATION:
		descent_position = Vector2(impact_position.x, minf(_camera_top() - 48.0, impact_position.y - 180.0))
		actor.global_position = descent_position
		actor.reset_physics_interpolation()
		actor.show()
		_enter(State.DESCENDING)


func _update_descent(delta: float) -> void:
	state_time += delta
	elapsed += delta
	var t := clampf(state_time / DESCENT_DURATION, 0.0, 1.0)
	actor.global_position = descent_position.lerp(impact_position, t * t)
	if state_time >= DESCENT_DURATION:
		actor.global_position = impact_position
		shadow.show()
		_set_pose(HIT_1_TEXTURE, HIT_1_FRAME_FOOT)
		_enter(State.HIT_1)


func _finish_hit_1() -> void:
	_set_pose(HIT_2_TEXTURE, HIT_2_FRAME_FOOT)
	_enter(State.HIT_2)
	_impact()


func _finish_hit_2() -> void:
	_set_ground_pose(WALK_FRAMES[0])
	_enter(State.RECOVERY)


func _finish_skybreaker() -> void:
	_enter_chase()
	skybreaker_finished.emit()


func _finish_melee_recovery() -> void:
	_enter_chase()


func _enter_chase() -> void:
	ai.reset_decision_timer()
	ai_world_sensor.reset_route()
	_sense_left = 0.0
	actor.z_index = ACTOR_DRAW_LAYER
	actor.show()
	shadow.show()
	_set_ground_pose(WALK_FRAMES[0])
	_enter(State.CHASE)
	_enable_body_when_clear()
	_restore_camera()


func _update_chase(delta: float) -> void:
	_enable_body_when_clear()
	_sense_left -= delta
	if _sense_left <= 0.0 or _observation == null:
		var sense_delta: float = 0.12
		var can_plan_special: bool = ai.special_cooldown_remaining <= 0.12 and actor.global_position.distance_to(player.global_position) >= ai.skybreaker_min_distance
		var landing_valid: bool = can_plan_special and _has_safe_landing_near(player.global_position + Vector2(0.0, 7.0))
		_observation = ai_world_sensor.build_observation(actor, player,
			EnemyAIEnums.Objective.PRESSURE_TARGET, melee_range, landing_valid, sense_delta)
		_sense_left = sense_delta
		ai.reset_decision_timer()
	_decision = ai.evaluate(_observation, delta)
	var decision: EnemyAIDecision = _decision
	actor.set_meta(&"enemy_ai_intent", decision.intent)
	if _execute_ai_attack(decision, _observation):
		return
	var movement_speed: float = chase_speed
	if decision.intent == EnemyAIEnums.Intent.RECOVER:
		movement_speed *= 0.55
	if decision.lock_movement or decision.intent in [EnemyAIEnums.Intent.HOLD, EnemyAIEnums.Intent.DISABLED]:
		actor.velocity = Vector2.ZERO
	else:
		actor.velocity = ai_world_sensor.safe_velocity(actor, decision.movement_direction * movement_speed, delta)
	if actor.velocity.length_squared() > 0.0001:
		_update_facing(actor.velocity.x)
		actor.move_and_slide()
	state_time += delta
	var frame: int = int(state_time / WALK_FRAME_DURATION) % WALK_FRAMES.size() if actor.velocity.length_squared() > 0.01 else 0
	_set_ground_pose(WALK_FRAMES[frame])


func _execute_ai_attack(decision: EnemyAIDecision, observation: EnemyAIObservation) -> bool:
	if decision.intent != EnemyAIEnums.Intent.PREPARE:
		return false
	actor.velocity = Vector2.ZERO
	if decision.attack_id == ai.skybreaker_attack_id:
		return start_skybreaker()
	if decision.attack_id == ai.melee_attack_id:
		if actor.global_position.distance_to(player.global_position + Vector2(0, 3)) > melee_range or not ai_world_sensor._has_line_of_sight(actor, player, player.global_position):
			ai.reset_decision_timer()
			_sense_left = 0.0
			return false
		ai.notify_attack_committed(melee_decision_cooldown)
		_begin_melee_prepare(observation.target_position - observation.self_position)
		return true
	return false


func _begin_melee_prepare(to_player: Vector2) -> void:
	melee_damage_emitted = false
	_update_facing(to_player.x)
	_set_ground_pose(MELEE_PREPARE_FRAMES[0])
	_enter(State.MELEE_PREPARE)
	melee_started.emit()


func _update_melee_prepare(delta: float) -> void:
	state_time += delta
	var frame := mini(int(state_time / PREPARE_FRAME_DURATION), MELEE_PREPARE_FRAMES.size() - 1)
	_set_ground_pose(MELEE_PREPARE_FRAMES[frame])
	if state_time >= PREPARE_FRAME_DURATION * MELEE_PREPARE_FRAMES.size():
		_set_attack_pose(MELEE_ATTACK_FRAMES[0])
		_enter(State.MELEE_ATTACK)


func _update_melee_attack(delta: float) -> void:
	state_time += delta
	var frame := mini(int(state_time / ATTACK_FRAME_DURATION), MELEE_ATTACK_FRAMES.size() - 1)
	_set_attack_pose(MELEE_ATTACK_FRAMES[frame])
	if frame >= 2 and not melee_damage_emitted:
		_melee_impact()
	if state_time >= ATTACK_FRAME_DURATION * MELEE_ATTACK_FRAMES.size():
		_set_ground_pose(WALK_FRAMES[0])
		_enter(State.MELEE_RECOVERY)


func _melee_impact() -> void:
	melee_damage_emitted = true
	melee_damage_requested.emit(actor.global_position, melee_hit_range, melee_damage)
	if actor.global_position.distance_to(player.global_position + Vector2(0, 3)) <= melee_hit_range:
		player.receive_skybreaker_hit(melee_damage)


func _tick_timed_state(delta: float, duration: float, completion: Callable) -> void:
	state_time += delta
	elapsed += delta
	if state_time >= duration:
		completion.call()


func _enter(next_state: State) -> void:
	actor.set_meta(&"enemy_ai_is_attacking", next_state in [State.MELEE_PREPARE, State.MELEE_ATTACK])
	state = next_state
	state_time = 0.0


func _set_pose(texture: Texture2D, foot: Vector2) -> void:
	field_skybreaker_visual.hide()
	visual.show()
	visual.texture = texture
	visual.flip_h = facing_left
	_apply_foot_anchor(texture, foot)


func _show_field_skybreaker_launch() -> void:
	visual.hide()
	field_skybreaker_visual.show()
	field_skybreaker_visual.flip_h = not facing_left
	var anchor_x := 37.0
	if field_skybreaker_visual.flip_h:
		anchor_x = field_skybreaker_visual.texture.get_width() - anchor_x
	field_skybreaker_visual.offset = -Vector2(anchor_x, GROUND_FOOT_Y)


func _apply_foot_anchor(texture: Texture2D, foot: Vector2) -> void:
	var anchor := foot
	if visual.flip_h:
		anchor.x = texture.get_width() - anchor.x
	visual.offset = -anchor


func _set_ground_pose(texture: Texture2D) -> void:
	field_skybreaker_visual.hide()
	visual.show()
	var walk_frame := WALK_FRAMES.find(texture)
	var foot_x := 23.0
	if walk_frame >= 0:
		foot_x = WALK_FOOT_X[walk_frame]
	var jump_frame := SKYBREAKER_PREPARE_FRAMES.find(texture)
	if jump_frame >= 0:
		foot_x = 37.0
	visual.texture = texture
	# Ground jump preparation faces left in the source; walk/melee face right.
	visual.flip_h = not facing_left if jump_frame >= 0 else facing_left
	_apply_foot_anchor(texture, Vector2(foot_x, GROUND_FOOT_Y))


func _set_attack_pose(texture: Texture2D) -> void:
	var frame := MELEE_ATTACK_FRAMES.find(texture)
	_set_pose(texture, Vector2(ATTACK_FOOT_X[maxi(frame, 0)], GROUND_FOOT_Y))


func _update_facing(horizontal_delta: float) -> void:
	if not is_zero_approx(horizontal_delta):
		facing_left = horizontal_delta < 0.0


func _throne_is_visible() -> bool:
	var half_view := get_viewport_rect().size * 0.5 / camera.zoom
	var view_rect := Rect2(camera.get_screen_center_position() - half_view, half_view * 2.0).grow(-6.0)
	var throne_rect := Rect2(global_position + Vector2(-36, -82), Vector2(72, 92))
	return view_rect.intersects(throne_rect)


func _camera_top() -> float:
	var inverse := get_viewport().get_canvas_transform().affine_inverse()
	var size := get_viewport_rect().size
	return minf((inverse * Vector2.ZERO).y, (inverse * Vector2(size.x, 0)).y)


func _safe_landing(wanted: Vector2) -> Vector2:
	# Keep the larger boss clear of hole edges, throne and outside boundaries.
	var bounds: Rect2 = player.movement_bounds.grow(-14.0)
	var center := arena.to_global(arena.to_local(wanted).clamp(bounds.position, bounds.end))
	for ring in range(9):
		for step in range(16):
			var candidate := center + Vector2.from_angle(TAU * step / 16.0) * ring * 8.0
			if not bounds.has_point(arena.to_local(candidate)):
				continue
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = body_shape.shape
			query.transform = Transform2D(0, candidate)
			query.exclude = [actor.get_rid(), player.get_rid()]
			query.collision_mask = 1
			if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				return candidate
	return launch_position


func _has_safe_landing_near(wanted: Vector2) -> bool:
	var bounds: Rect2 = player.movement_bounds.grow(-14.0)
	var center: Vector2 = arena.to_global(arena.to_local(wanted).clamp(bounds.position, bounds.end))
	for ring in range(9):
		for step in range(16):
			var candidate: Vector2 = center + Vector2.from_angle(TAU * float(step) / 16.0) * float(ring) * 8.0
			if not bounds.has_point(arena.to_local(candidate)):
				continue
			var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
			query.shape = body_shape.shape
			query.transform = Transform2D(0.0, candidate)
			query.exclude = [actor.get_rid(), player.get_rid()]
			query.collision_mask = 1
			if get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				return true
	return false


func _impact() -> void:
	if damage_emitted:
		return
	damage_emitted = true
	impact_started.emit(impact_position)
	area_damage_requested.emit(impact_position, impact_radius, preview_damage)
	effect.global_position = impact_position
	effect.start(impact_radius)
	_shake(8.0, 1.5, 0.25)
	var shape := CircleShape2D.new()
	shape.radius = impact_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, impact_position)
	query.collision_mask = player.collision_layer
	query.exclude = [actor.get_rid(), get_rid()]
	for result in get_world_2d().direct_space_state.intersect_shape(query, 64):
		if result.collider == player:
			player.receive_skybreaker_hit(preview_damage)
			break


func _enable_body_when_clear() -> void:
	if not body_shape.disabled:
		return
	if actor.global_position.distance_to(player.global_position + Vector2(0, 3)) > 20.0:
		body_shape.set_deferred("disabled", false)


func _capture_camera() -> void:
	camera_offset = camera.offset
	camera_rotation = camera.rotation
	camera_ignore_rotation = camera.ignore_rotation


func _shake(pixels: float, degrees: float, duration: float) -> void:
	shake_time = duration
	shake_duration = duration
	shake_pixels = pixels
	shake_angle = deg_to_rad(degrees)
	camera.ignore_rotation = false


func _update_shake(delta: float) -> void:
	if shake_time <= 0.0:
		return
	shake_time = maxf(0.0, shake_time - delta)
	var t := shake_duration - shake_time
	var strength := pow(shake_time / shake_duration, 2.0) * shake_intensity
	camera.offset = camera_offset + Vector2(sin(t * 95), cos(t * 77)) * shake_pixels * strength
	camera.rotation = camera_rotation + sin(t * 51) * shake_angle * strength
	if shake_time <= 0.0:
		_restore_camera()


func _restore_camera() -> void:
	if is_instance_valid(camera):
		camera.offset = camera_offset
		camera.rotation = camera_rotation
		camera.ignore_rotation = camera_ignore_rotation


func _exit_tree() -> void:
	if state != State.SITTING:
		_restore_camera()


func enter_weapon_reveal() -> void:
	_enter(State.WEAPON_REVEAL)


func enter_intro_dialogue_state() -> void:
	_enter(State.INTRO_DIALOGUE)


func enter_horde_phase() -> void:
	_enter(State.HORDE)


func enter_return_phase() -> void:
	_enter(State.WAIT_RETURN)
