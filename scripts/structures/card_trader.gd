extends Node2D
## A complete interaction owns the pause from opening through the closing frames.

const ACTIVATION_RADIUS: float = 56.0

var state: StringName = &"machine"
var ground_height: float = 0.0
var _player: Player
var _world: Node2D
var _controller: Node
var _session_active: bool = false
var _previous_pause: bool = false
var _elapsed: float = 0.0

@onready var _visuals: Node2D = $Visuals
@onready var _sprite: AnimatedSprite2D = $Visuals/Machine
@onready var _screen_light: PointLight2D = $Visuals/ScreenLight
@onready var _antenna_light: PointLight2D = $Visuals/AntennaLight
@onready var _action: Sprite2D = $ActionPrompt


func _ready() -> void:
	add_to_group(&"card_traders")
	_sprite.animation_finished.connect(_on_animation_finished)


func configure(subject: Player, world: Node2D, description: Dictionary) -> void:
	_player = subject
	_world = world
	position = description["position"] as Vector2
	scale = Vector2.ONE * float(description.get("DisplayScale", 1.0))
	ground_height = float(description.get("TerrainHeight", 0.0))
	_visuals.position.y = -ground_height / absf(global_scale.y)
	_action.scale = Vector2.ONE / global_scale.abs()
	_action.call("configure", Vector2(0, -ground_height / absf(global_scale.y) - 70.0))
	_controller = _player.get_node("GameplayKit/Manifestations")
	_controller.connect("equipment_menu_closed", _on_menu_closed)


func can_interact() -> bool:
	return state == &"machine" and is_instance_valid(_player) and is_instance_valid(_controller) \
		and not get_tree().paused and not _player.dead and not _player.intro_locked and not _player.is_dashing() \
		and bool(_world.get("entry_complete")) and not bool(_world.get("_travel_busy")) \
		and get_tree().get_first_node_in_group(&"card_table_modal") == null \
		and absf(_player.displayed_height - ground_height) <= 8.0 \
		and _player.to_global(Vector2(0, 3)).distance_to(global_position) <= ACTIVATION_RADIUS


func interact() -> bool:
	if not can_interact():
		return false
	_previous_pause = get_tree().paused
	_session_active = true
	add_to_group(&"card_table_modal")
	_controller.call("suspend_trigger")
	_action.call("set_available", false)
	get_tree().paused = true
	state = &"opening"
	_sprite.play(&"opening")
	return true


func _on_animation_finished() -> void:
	if state == &"opening":
		# Hand pause ownership to the existing menu synchronously, between frames.
		get_tree().paused = _previous_pause
		state = &"opened"
		_sprite.play(&"opened")
		if not bool(_controller.call("open_equipment_menu")):
			_start_closing()
	elif state == &"closing":
		_sprite.stop()
		_sprite.animation = &"machine"
		_sprite.frame = 0
		state = &"machine"
		remove_from_group(&"card_table_modal")
		_session_active = false
		get_tree().paused = _previous_pause
		_controller.call("suspend_trigger")


func _on_menu_closed() -> void:
	if is_inside_tree() and state == &"opened":
		_start_closing()


func _start_closing() -> void:
	state = &"closing"
	get_tree().paused = true
	_sprite.play(&"closing")


func _process(delta: float) -> void:
	_elapsed += delta
	if is_instance_valid(_player):
		z_index = _player.z_index + (1 if _player.to_global(Vector2(0, 3)).y < global_position.y else -1)
	_action.call("set_available", can_interact())
	var breathe: float = 1.0 + sin(_elapsed * 2.0) * 0.06
	_screen_light.energy = (0.13 if state == &"opened" else 0.09) * breathe
	_antenna_light.energy = 0.04 * breathe


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or (key.physical_keycode != KEY_E and key.keycode != KEY_E):
		return
	if interact():
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _session_active:
		get_tree().paused = _previous_pause
