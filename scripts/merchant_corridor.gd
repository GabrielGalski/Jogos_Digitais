extends Node2D

const FLOOR_GEOMETRY: Script = preload("res://scripts/merchant_floor_geometry.gd")
const AWNING_SCENE: PackedScene = preload("res://scenes/merchant/toldo.tscn")
const WATER_SCENE: PackedScene = preload("res://scenes/merchant/water.tscn")
const DUNGEON_SCENE: String = "res://scenes/dungeon/dungeon_preview.tscn"

enum CorridorState { FADE_IN, ENTERING, PLAYING, RESTARTING, TALKING }

const NOX_START: Vector2 = Vector2(-14.0, 28.0)
const NOX_STOP: Vector2 = Vector2(72.0, 28.0)
const EXIT_FADE_X: float = float(FLOOR_GEOMETRY.ROOM_SIZE.x) - 48.0
const FOOT_MARGIN: float = 4.0
const CLOSED_ENTRANCE_X: float = 20.0

@export var movement_speed: float = 112.5
@export var entrance_speed: float = 82.0
@export var height_change_speed: float = 120.0
@export var camera_response: float = 6.5
@export var camera_look_ahead: float = 16.0
@export var camera_movement_lift: float = 8.0
@export var mouse_top_lift: float = 12.0
@export_range(0.05, 0.5) var mouse_top_zone: float = 0.3

# X is distance along the corridor; Y is depth on the floor, not screen Y.
var ground_position: Vector2 = NOX_START
var floor_level: int = 3
var floor_height: float = 36.0
var displayed_height: float = 36.0
var state: CorridorState = CorridorState.FADE_IN
var restart_started: bool = false
var movement_direction: Vector2 = Vector2.ZERO
var mouse_look_up: float = 0.0

@onready var nox: Node2D = $Nox
@onready var nox_visual: AnimatedSprite2D = $Nox/Visual
@onready var hall_shooter: Node2D = $HallShooter
@onready var entrance_cutscene: Node2D = $EntranceCutscene
@onready var entrance_door: Node2D = $World/Entrance/DoorPanel
@onready var fade: ColorRect = $FadeLayer/Fade
@onready var room_camera: Camera2D = $RoomCamera
@onready var merchant: MerchantInteractable = $World/Merchant
@onready var dialogue: DialogueBox = $TinDialogue
@onready var interaction_prompt: Label = $InteractionHUD/PromptAnchor/Prompt


func _ready() -> void:
	dialogue.dialogue_finished.connect(_on_tin_dialogue_finished)
	_configure_presentation()
	get_viewport().size_changed.connect(_fit_hall_camera)
	_reset_nox()
	entrance_cutscene.call("begin", nox, hall_shooter)
	hall_shooter.call("reset_follow", nox.global_position)
	entrance_door.hide()
	fade.color = Color.BLACK
	await _fade_to(0.0, 0.45)
	state = CorridorState.ENTERING


func _physics_process(delta: float) -> void:
	match state:
		CorridorState.ENTERING:
			_update_entrance(delta)
		CorridorState.PLAYING:
			_update_player(delta)
	_update_height(delta)
	var shooter_direction: Vector2 = Vector2.RIGHT if state == CorridorState.ENTERING else movement_direction
	hall_shooter.call("update_follow", nox.global_position, shooter_direction, delta)
	entrance_cutscene.call("update_layers", nox, hall_shooter)
	_update_camera(delta)
	interaction_prompt.visible = state == CorridorState.PLAYING and merchant.initial_dialogue != null and merchant.can_interact(nox)


func _unhandled_input(event: InputEvent) -> void:
	if state != CorridorState.PLAYING or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo or (key.physical_keycode != KEY_E and key.keycode != KEY_E):
		return
	if not merchant.can_interact(nox) or merchant.initial_dialogue == null:
		return
	get_viewport().set_input_as_handled()
	state = CorridorState.TALKING
	movement_direction = Vector2.ZERO
	nox_visual.play(&"idle")
	interaction_prompt.hide()
	dialogue.start_dialogue(merchant.initial_dialogue)


func _on_tin_dialogue_finished(_sequence_id: StringName) -> void:
	if state == CorridorState.TALKING:
		state = CorridorState.PLAYING


func _update_camera(delta: float) -> void:
	var half_width: float = get_viewport_rect().size.x / room_camera.zoom.x * 0.5
	var active: bool = state == CorridorState.PLAYING
	var movement: Vector2 = movement_direction if active else Vector2.ZERO
	var cursor_lift: float = mouse_look_up if active else 0.0
	var left: float = -float(FLOOR_GEOMETRY.CAMERA_MARGIN) + half_width
	var right: float = float(FLOOR_GEOMETRY.ROOM_SIZE.x + FLOOR_GEOMETRY.CAMERA_MARGIN) - half_width
	var target: Vector2 = Vector2(clampf(nox.position.x + movement.x * camera_look_ahead, left, right), 135.0)
	# In 2D, looking up is a vertical framing offset, never a lateral roll.
	var depth_lift: float = maxf(28.0 - ground_position.y, 0.0) * 0.15 if active else 0.0
	target.y -= movement.length() * camera_movement_lift + cursor_lift * mouse_top_lift + depth_lift
	var weight: float = 1.0 - exp(-camera_response * delta)
	room_camera.position = room_camera.position.lerp(target, weight)
	# Full-height framing takes priority over vertical look at the image boundary.
	room_camera.position.y = 135.0


func _fit_hall_camera() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var fit_zoom: float = maxf(viewport_size.y / float(FLOOR_GEOMETRY.RENDER_SIZE.y),
		viewport_size.x / float(FLOOR_GEOMETRY.RENDER_SIZE.x))
	room_camera.zoom = Vector2.ONE * fit_zoom


func _configure_presentation() -> void:
	_fit_hall_camera()
	nox_visual.scale = Vector2.ONE * 2.1
	nox_visual.position.y = -16.8
	var merchant_visual: AnimatedSprite2D = $World/Merchant/Visual
	merchant_visual.modulate = Color(0.86, 0.78, 0.86, 1.0)
	var awning: Node2D = AWNING_SCENE.instantiate() as Node2D
	awning.position = Vector2(233.0, 5.0)
	$World.add_child(awning)
	var water: Node2D = WATER_SCENE.instantiate() as Node2D
	water.position = Vector2(-32.0, -32.0)
	$World.add_child(water)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var viewport_size: Vector2 = get_viewport_rect().size
		var relative_y: float = motion.position.y / maxf(viewport_size.y, 1.0)
		mouse_look_up = 1.0 - smoothstep(0.0, mouse_top_zone, relative_y)


func _update_height(delta: float) -> void:
	floor_level = FLOOR_GEOMETRY.level_at(ground_position.x)
	floor_height = FLOOR_GEOMETRY.height_at(ground_position.x)
	displayed_height = move_toward(displayed_height, floor_height, height_change_speed * delta)
	nox.position = FLOOR_GEOMETRY.project_floor(ground_position, displayed_height)


func _reset_nox() -> void:
	ground_position = NOX_START
	floor_level = FLOOR_GEOMETRY.level_at(ground_position.x)
	floor_height = FLOOR_GEOMETRY.height_at(ground_position.x)
	displayed_height = floor_height
	nox.position = FLOOR_GEOMETRY.project_floor(ground_position, displayed_height)
	nox_visual.flip_h = false
	nox_visual.play(&"idle")
	movement_direction = Vector2.ZERO
	mouse_look_up = 0.0
	room_camera.position = Vector2(-32.0 + get_viewport_rect().size.x / room_camera.zoom.x * 0.5, 135.0)
	room_camera.rotation = 0.0
	room_camera.reset_physics_interpolation()
	nox.reset_physics_interpolation()
	room_camera.reset_smoothing()
	room_camera.force_update_scroll()


func _update_entrance(delta: float) -> void:
	nox_visual.play(&"run")
	ground_position = ground_position.move_toward(NOX_STOP, entrance_speed * delta)
	_set_facing(1.0)
	if ground_position.is_equal_approx(NOX_STOP):
		nox_visual.play(&"idle")
		state = CorridorState.FADE_IN
		await get_tree().create_timer(0.18).timeout
		await _close_entrance()
		entrance_cutscene.call("finish", nox, hall_shooter)
		state = CorridorState.PLAYING


func _update_player(delta: float) -> void:
	var direction: Vector2 = Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	).normalized()
	_move_on_floor(direction, delta)
	if FLOOR_GEOMETRY.project_floor(ground_position, 0.0).x >= EXIT_FADE_X and not restart_started:
		restart_started = true
		_restart_corridor.call_deferred()


func _move_on_floor(direction: Vector2, delta: float) -> void:
	var old_ground: Vector2 = ground_position
	# Compensate the depth skew so W/S stays vertical on each level.
	var next_depth: float = clampf(ground_position.y + direction.y * movement_speed * delta,
		FOOT_MARGIN, FLOOR_GEOMETRY.FLOOR_DEPTH - FOOT_MARGIN)
	ground_position.x += direction.x * movement_speed * delta + (next_depth - ground_position.y) * FLOOR_GEOMETRY.DEPTH_SKEW
	ground_position.y = next_depth
	ground_position.x = maxf(ground_position.x, CLOSED_ENTRANCE_X + ground_position.y * FLOOR_GEOMETRY.DEPTH_SKEW)
	_set_facing(direction.x)
	movement_direction = Vector2.ZERO if ground_position.is_equal_approx(old_ground) else direction
	nox_visual.play(&"idle" if ground_position.is_equal_approx(old_ground) else &"run")


func _set_facing(horizontal_direction: float) -> void:
	if not is_zero_approx(horizontal_direction):
		nox_visual.flip_h = horizontal_direction < 0.0


func _close_entrance() -> void:
	entrance_door.show()
	entrance_door.position = Vector2(0.0, -58.0)
	var door_tween: Tween = create_tween()
	door_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	door_tween.tween_property(entrance_door, "position", Vector2.ZERO, 0.32)
	await door_tween.finished


func _restart_corridor() -> void:
	state = CorridorState.RESTARTING
	nox_visual.play(&"idle")
	await _fade_to(1.0, 0.5)
	get_tree().change_scene_to_file(DUNGEON_SCENE)


func _fade_to(alpha: float, duration: float) -> void:
	var fade_tween: Tween = create_tween()
	fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(fade, "color:a", alpha, duration)
	await fade_tween.finished
