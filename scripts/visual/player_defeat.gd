extends CanvasLayer
## Scene-owned defeat presentation and arrival checkpoint. No campaign singleton.

const SILHOUETTE: Shader = preload("res://shaders/defeat_silhouette.gdshader")
const SLASH: Script = preload("res://scripts/visual/defeat_slash.gd")
const FONT: Font = preload("res://assets/font/determination.ttf")
const SLOW_SCALE: float = 0.12
const MENU_TIME: float = 1.05

var active: bool = false
var menu_ready: bool = false
var _retrying: bool = false
var _player: Player = null
var _arena: Node = null
var _checkpoint_properties: Dictionary = {}
var _checkpoint_state: Dictionary = {}
var _checkpoint_path: String = ""
var _started_ms: int = 0
var _previous_scale: float = 1.0
var _previous_pause: bool = false
var _previous_camera: Camera2D = null
var _camera: Camera2D = null
var _start_position: Vector2 = Vector2.ZERO
var _start_zoom: Vector2 = Vector2.ONE
var _cover: ColorRect = null
var _portrait: Sprite2D = null
var _slash: Node2D = null
var _menu: CenterContainer = null
var _retry: Button = null
var _fade: ColorRect = null
var _cursor: Polygon2D = null
var _hidden_layers: Array[CanvasLayer] = []


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func bind_player(actor: Player, arena: Node) -> void:
	_player = actor
	_arena = arena
	_checkpoint_path = arena.scene_file_path
	actor.defeated.connect(_on_defeated, CONNECT_DEFERRED)


func capture_checkpoint(properties: Dictionary = {}) -> void:
	_checkpoint_properties = properties.duplicate(true)
	var shooter: Node = _player.get_node("BoosterShooter")
	var runtime: CardCombatRuntime = shooter.get("card_runtime") as CardCombatRuntime
	var saved_runtime: CardCombatRuntime = CardCombatRuntime.new()
	if runtime != null and runtime.get("_loadout") != null:
		saved_runtime.equip((runtime.get("_loadout") as CardLoadout).duplicate(true) as CardLoadout)
	_checkpoint_state = {"max_health": _player.max_health, "health": _player.max_health,
		"dash_charges": Player.MAX_DASH_CHARGES, "dash_recovery": 0.0, "cooldown": 0.0,
		"card_runtime": saved_runtime}


func _on_defeated() -> void:
	if active:
		return
	active = true
	_previous_scale = Engine.time_scale
	_previous_pause = get_tree().paused
	_started_ms = Time.get_ticks_msec()
	_player.intro_locked = true
	_player.knockback_velocity = Vector2.ZERO
	_player.body.end_roll()
	_player.body.stop()
	_player.body.animation_locked = true
	_player.body.modulate = Color.WHITE
	if _player.hit_flash != null and _player.hit_flash.is_valid():
		_player.hit_flash.kill()
	var white: ShaderMaterial = ShaderMaterial.new()
	white.shader = SILHOUETTE
	_player.body.material = white
	_player.get_node("BoosterShooter").call("set_combat_enabled", false)
	(_player.get_node("BoosterShooter") as CanvasItem).hide()
	for node: Node in _arena.find_children("*", "CanvasLayer", true, false):
		var hud: CanvasLayer = node as CanvasLayer
		if hud != self and hud.layer >= 40 and hud.visible:
			_hidden_layers.append(hud)
			hud.hide()
	_previous_camera = get_viewport().get_camera_2d()
	_start_position = _previous_camera.get_screen_center_position()
	_start_zoom = _previous_camera.zoom
	_camera = Camera2D.new()
	_camera.name = "DefeatCamera"
	_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arena.add_child(_camera)
	_camera.global_position = _start_position
	_camera.zoom = _start_zoom
	_camera.make_current()
	_build_presentation(white)
	Engine.time_scale = SLOW_SCALE
	get_tree().paused = false
	set_process(true)


func _build_presentation(white: ShaderMaterial) -> void:
	_cover = ColorRect.new()
	_cover.name = "RedScreen"
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	_portrait = Sprite2D.new()
	_portrait.name = "WhiteSilhouette"
	_portrait.texture = _player.body.sprite_frames.get_frame_texture(_player.body.animation, _player.body.frame)
	_portrait.flip_h = _player.body.flip_h
	_portrait.flip_v = _player.body.flip_v
	_portrait.centered = _player.body.centered
	_portrait.offset = _player.body.offset
	_portrait.material = white
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_portrait)
	_slash = SLASH.new() as Node2D
	_slash.name = "DiagonalSlash"
	add_child(_slash)
	_menu = CenterContainer.new()
	_menu.name = "RetryMenu"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.anchor_top = 0.68
	_menu.anchor_bottom = 0.94
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 8)
	_menu.add_child(column)
	_retry = Button.new()
	_retry.name = "Retry"
	_retry.text = "Tentar Novamente"
	_retry.custom_minimum_size = Vector2(164.0, 32.0)
	_retry.add_theme_font_override("font", FONT)
	_retry.add_theme_font_size_override("font_size", 18)
	for style_name: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("321522") if style_name != "hover" else Color("60233b")
		style.border_color = Color("f9eff5") if style_name == "focus" else Color("a65c78")
		style.set_border_width_all(2 if style_name == "focus" else 1)
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		_retry.add_theme_stylebox_override(style_name, style)
	column.add_child(_retry)
	_retry.pressed.connect(retry)
	_menu.hide()
	_fade = ColorRect.new()
	_fade.name = "RetryFade"
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_cursor = Polygon2D.new()
	_cursor.name = "RetryCursor"
	_cursor.polygon = PackedVector2Array([Vector2.ZERO, Vector2(0, 10), Vector2(3, 7), Vector2(7, 7)])
	_cursor.color = Color.WHITE
	_cursor.hide()
	add_child(_cursor)


func _process(_delta: float) -> void:
	var elapsed: float = float(Time.get_ticks_msec() - _started_ms) / 1000.0
	var approach: float = 1.0 - pow(1.0 - clampf(elapsed / 0.65, 0.0, 1.0), 3.0)
	_camera.global_position = _start_position.lerp(_player.body.global_position, approach)
	_camera.zoom = _start_zoom.lerp(_start_zoom * 1.8, approach)
	_camera.force_update_scroll()
	_cover.color = Color(0.36, 0.015, 0.065, lerpf(0.0, 0.88, clampf(elapsed / 0.3, 0.0, 1.0)))
	_portrait.transform = _player.body.get_global_transform_with_canvas()
	_slash.position = _portrait.position.round()
	_slash.set("pixel_scale", _camera.zoom.x)
	_slash.set("progress", (elapsed - 0.30) / 0.42 if elapsed >= 0.30 else -1.0)
	_slash.queue_redraw()
	_cursor.position = get_viewport().get_mouse_position().round()
	if elapsed >= 0.7 and not get_tree().paused:
		get_tree().paused = true
	if elapsed >= MENU_TIME and not menu_ready:
		menu_ready = true
		_menu.show()
		_cursor.show()
		_retry.grab_focus()


func retry() -> void:
	if not menu_ready or _retrying:
		return
	var packed: PackedScene = load(_checkpoint_path) as PackedScene
	if packed == null:
		push_error("Warp de retorno indisponivel: " + _checkpoint_path)
		return
	_retrying = true
	_retry.disabled = true
	var fade: Tween = create_tween().set_ignore_time_scale(true)
	fade.tween_property(_fade, "color:a", 1.0, 0.18)
	await fade.finished
	var next_scene: Node = packed.instantiate()
	for key: String in _checkpoint_properties:
		next_scene.set(key, _checkpoint_properties[key])
	if "entry_player_state" in next_scene:
		next_scene.set("entry_player_state", _checkpoint_state.duplicate(true))
	var tree: SceneTree = get_tree()
	var parent: Node = _arena.get_parent()
	_restore_clock()
	parent.remove_child(_arena)
	parent.add_child(next_scene)
	tree.current_scene = next_scene
	_arena.queue_free()


func _restore_clock() -> void:
	if not active:
		return
	Engine.time_scale = _previous_scale
	get_tree().paused = _previous_pause
	active = false


func _exit_tree() -> void:
	_restore_clock()
	for hud: CanvasLayer in _hidden_layers:
		if is_instance_valid(hud):
			hud.show()
	if is_instance_valid(_camera):
		_camera.queue_free()
