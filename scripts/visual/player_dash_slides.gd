extends Node2D
## Exactly three current-frame actor silhouettes using the authored roll1/2/3 palette.

const TEXTURES: Array[Texture2D] = [
	preload("res://assets/characters/player/roll/roll1.png"),
	preload("res://assets/characters/player/roll/roll2.png"),
	preload("res://assets/characters/player/roll/roll3.png"),
]
const OUTER_GLOW: Script = preload("res://scripts/visual/sprite_outer_glow.gd")
const LIGHT_RIG: Script = preload("res://scripts/visual/arena_lighting_rig.gd")
const SLIDE_SHADER: Shader = preload("res://shaders/player_dash_slide.gdshader")
const PALETTE: Array[Color] = [Color.WHITE, Color("#24132e"), Color("#5b2038")]
@export var echo_spacing: float = 5.5
@export var settle_duration: float = 0.10
@export var light_energy: float = 0.38
var echoes: Array[Sprite2D] = []
var glows: Array[Sprite2D] = []
var light: PointLight2D = null
var points: Array[Vector2] = []
var _active: bool = false
var _settle_remaining: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
@onready var player: Player = get_parent() as Player
@onready var body: NoxVisual = get_node("../Body") as NoxVisual


func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_physics_priority = 3
	z_as_relative = false
	z_index = player.z_index - 1
	var core: CanvasItemMaterial = CanvasItemMaterial.new()
	core.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var bloom: CanvasItemMaterial = core.duplicate() as CanvasItemMaterial
	bloom.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for index: int in range(3):
		var glow: Sprite2D = Sprite2D.new()
		glow.name = "Glow%d" % (index + 1)
		glow.texture = OUTER_GLOW.texture_for(TEXTURES[index])
		glow.material = bloom
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		glow.z_index = -1
		add_child(glow)
		glows.append(glow)
		if index == 0:
			continue
		var echo: Sprite2D = Sprite2D.new()
		echo.name = "Slide%d" % (index + 1)
		echo.texture = TEXTURES[index]
		var tint_material: ShaderMaterial = ShaderMaterial.new()
		tint_material.shader = SLIDE_SHADER
		tint_material.set_shader_parameter(&"slide_tint", PALETTE[index])
		tint_material.set_shader_parameter(&"slide_mix", 1.0)
		echo.material = tint_material
		echo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		echo.z_index = 1 - index
		add_child(echo)
		echoes.append(echo)
	light = PointLight2D.new()
	light.name = "SlidePulse"
	light.texture = LIGHT_RIG.make_radial_texture()
	light.texture_scale = 0.28
	light.color = Color("#ead7f5")
	light.energy = 0.0
	light.shadow_enabled = false
	light.range_z_min = -2
	light.range_z_max = 2
	add_child(light)
	player.dash_started.connect(_begin_dash)
	player.defeated.connect(reset_effect)
	body.frame_changed.connect(_sync_frame)
	reset_effect()


func _begin_dash() -> void:
	points.clear()
	points.append(player.surface_world_position())
	_last_position = player.global_position
	_active = true
	_settle_remaining = 0.0
	body.add_to_group(&"dash_slides")
	for echo: Sprite2D in echoes:
		echo.add_to_group(&"dash_slides")
	_update_poses(0.0)


func _physics_process(delta: float) -> void:
	var distance: float = player.global_position.distance_to(_last_position)
	_last_position = player.global_position
	if player.intro_locked or player.dead or distance > player.dash_speed * delta * 2.0:
		reset_effect()
		return
	if _active:
		if points.back().distance_squared_to(player.surface_world_position()) > 0.01:
			points.append(player.surface_world_position())
			if points.size() > 12:
				points.pop_front()
		if not player.is_dashing():
			_active = false
			_settle_remaining = settle_duration
			body.remove_from_group(&"dash_slides")


func _process(delta: float) -> void:
	if player.dead or player.intro_locked or not body.is_visible_in_tree():
		reset_effect()
		return
	if not _active:
		_settle_remaining = maxf(0.0, _settle_remaining - delta)
		if _settle_remaining <= 0.0:
			reset_effect()
			return
	_update_poses(delta)


func _update_poses(_delta: float) -> void:
	var elapsed: float = player.dash_duration - player.dash_remaining
	var settling: float = clampf(_settle_remaining / maxf(settle_duration, 0.001), 0.0, 1.0)
	var reveal: float = smoothstep(0.0, 0.025, elapsed) if _active else settling * settling
	var spread: float = smoothstep(0.0, 0.035, elapsed) if _active else settling * settling
	var size_factor: float = player.body_rest_scale.x
	var frame_texture: Texture2D = body.sprite_frames.get_frame_texture(body.animation, body.frame)
	var frame_glow: Texture2D = OUTER_GLOW.texture_for(frame_texture)
	for index: int in range(echoes.size()):
		var echo: Sprite2D = echoes[index]
		echo.texture = frame_texture
		echo.visible = reveal > 0.01
		echo.position = _point_behind(echo_spacing * float(index + 1) * size_factor * spread)
		echo.scale = player.body_rest_scale
		echo.flip_h = body.flip_h
		echo.rotation = 0.0
		echo.modulate = Color(1, 1, 1, reveal * (0.86 if index == 0 else 0.68))
		var glow: Sprite2D = glows[index + 1]
		glow.texture = frame_glow
		glow.visible = echo.visible
		glow.position = echo.position
		glow.scale = echo.scale
		glow.flip_h = echo.flip_h
		glow.modulate = Color(0.75, 0.55, 0.88, reveal * 0.18)
	var progress: float = clampf(elapsed / maxf(player.dash_duration, 0.001), 0.0, 1.0)
	var leading_glow: Sprite2D = glows[0]
	leading_glow.texture = frame_glow
	var brightness: float = reveal * (1.0 - smoothstep(0.72, 1.0, progress)) if _active else settling * settling * 0.3
	leading_glow.visible = brightness > 0.01
	leading_glow.position = body.global_position
	leading_glow.scale = body.global_scale
	leading_glow.flip_h = body.flip_h
	leading_glow.modulate = Color(1, 0.94, 1, brightness * 0.44)
	light.global_position = player.surface_world_position()
	light.energy = light_energy * reveal * (0.65 + 0.35 * brightness)


func _sync_frame() -> void:
	if _active or _settle_remaining > 0.0:
		_update_poses(0.0)


func _point_behind(distance: float) -> Vector2:
	if points.is_empty():
		return player.surface_world_position()
	var head: Vector2 = player.surface_world_position()
	var remaining: float = distance
	for index: int in range(points.size() - 1, -1, -1):
		var tail: Vector2 = points[index]
		var length: float = head.distance_to(tail)
		if length >= remaining and length > 0.001:
			return head.lerp(tail, remaining / length)
		remaining -= length
		head = tail
	return head


func reset_effect() -> void:
	_active = false
	_settle_remaining = 0.0
	points.clear()
	_last_position = player.global_position
	if body.is_in_group(&"dash_slides"):
		body.remove_from_group(&"dash_slides")
	for echo: Sprite2D in echoes:
		echo.hide()
		echo.remove_from_group(&"dash_slides")
	for glow: Sprite2D in glows:
		glow.hide()
	if light != null:
		light.energy = 0.0
