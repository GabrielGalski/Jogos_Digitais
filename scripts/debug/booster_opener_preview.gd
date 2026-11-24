extends Node2D
## Standalone comparison of the original raised mockup and the marked opener.

const START_POSITION: Vector2 = Vector2(108, 30)
const PEDESTAL_TEXTURE: Texture2D = preload("res://assets/tiles/floor/pedestal.png")
const GAMEPLAY_CAMERA_RIG: Script = preload("res://scripts/visual/gameplay_camera_rig.gd")
const PREVIEW_FLOOR_BOUNDS: Rect2 = Rect2(-512, -320, 1024, 640)
const ROOM_LIGHTING: Script = preload("res://scripts/visual/room_lighting.gd")
const LIGHTING_PROFILE: Resource = preload("res://resources/visual/room_1_lighting.tres")
const LIGHTING_SETUPS: Resource = preload("res://resources/visual/room_lighting_setups.tres")
const MARKED_POSITION: Vector2 = Vector2(136, 0)
const REWARD_PEDESTAL: Script = preload("res://scripts/structures/booster_reward_pedestal.gd")

@onready var player: Player = $Actors/Nox
@onready var platform: Node2D = $Actors/HordePlatform
@onready var camera: Camera2D = $Actors/Nox/Camera2D
@onready var marked_opener: Node2D = $Actors/MarkedBoosterOpener
var combat_enabled: bool = false
var altar: Node2D = null
var _cursor_configured: bool = false
var _previous_cursor_visibility: bool = true
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	get_window().title = "Monster Booster - Altar de cartas (previa)"
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_WINDOWED
	var camera_rig: Node = GAMEPLAY_CAMERA_RIG.new() as Node
	camera_rig.name = "GameplayCameraRig"
	camera_rig.set("player", player)
	camera_rig.set("world_bounds", PREVIEW_FLOOR_BOUNDS)
	add_child(camera_rig)
	var shooter: Node2D = player.get_node("BoosterShooter") as Node2D
	shooter.process_mode = Node.PROCESS_MODE_DISABLED
	shooter.hide()
	var plate: Sprite2D = Sprite2D.new()
	plate.texture = PEDESTAL_TEXTURE
	plate.scale = Vector2.ONE * 0.5
	plate.z_index = -12
	platform.add_child(plate)
	platform.call("configure", {"position": Vector2.ZERO})
	altar = platform.get_node("BoosterOpener") as Node2D
	altar.get_node("Visuals/ExclamationMarker").call("set_active", false)
	altar.set("interaction_enabled", true)
	altar.set("action_prompt_enabled", true)
	altar.call("bind_player", player)
	marked_opener.call("fit_on_platform", REWARD_PEDESTAL.WORLD_BODY_WIDTH, MARKED_POSITION, 0.0)
	marked_opener.call("bind_player", player)
	var lighting: CanvasLayer = ROOM_LIGHTING.new() as CanvasLayer
	lighting.name = "RoomLighting"
	lighting.set("profile", LIGHTING_PROFILE)
	lighting.set("setups", LIGHTING_SETUPS)
	lighting.set("subject", player)
	add_child(lighting)
	_previous_cursor_visibility = GameCursor.visible
	_previous_mouse_mode = Input.mouse_mode
	_cursor_configured = true
	GameCursor.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	if _cursor_configured and is_instance_valid(GameCursor):
		GameCursor.visible = _previous_cursor_visibility
		Input.mouse_mode = _previous_mouse_mode


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or (key.physical_keycode != KEY_R and key.keycode != KEY_R):
		return
	get_viewport().set_input_as_handled()
	player.position = START_POSITION
	player.velocity = Vector2.ZERO
	player.dash_remaining = 0.0
	player.body.end_roll()
	player.body.set_motion(Vector2.ZERO)
	player.snap_floor_height()
	player.reset_physics_interpolation()
	camera.reset_smoothing()
	camera.force_update_scroll()
	if is_instance_valid(altar):
		altar.call("reset_preview")
