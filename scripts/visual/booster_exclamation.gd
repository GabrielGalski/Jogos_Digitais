extends Node2D
## World-sized animated markers for idle and active encounters.

const PALETTE: Shader = preload("res://shaders/booster_exclamation_yellow.gdshader")
const LIGHT_TEXTURE: Texture2D = preload("res://resources/visual/booster_opener_light.tres")
const OUTER_GLOW: Script = preload("res://scripts/visual/sprite_outer_glow.gd")
const FRAME_PATH: String = "res://assets/tiles/structures/booster_opener/exclamation/exclam%d.png"
const WARNING_PATH: String = "res://assets/tiles/structures/booster_opener/warning/WarningSign%02d.png"
const NATIVE_SIZE: int = 32
const DISPLAY_SIZE: float = 20.0
const HEIGHT_ABOVE_BODY: float = 36.0
@export var combat_warning: bool = false

var _elapsed: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
var _sprite: AnimatedSprite2D = null
var _glow: Sprite2D = null
var _light: PointLight2D = null
var _glow_frames: Array[Texture2D] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_as_relative = false
	z_index = 32
	var surface: AnimatedSprite2D = get_parent().get_node("Surface") as AnimatedSprite2D
	var body_texture: Texture2D = surface.sprite_frames.get_frame_texture(&"closed", 0)
	var body_image: Image = body_texture.get_image()
	if body_image.is_compressed():
		body_image.decompress()
	_anchor = surface.position - body_texture.get_size() * 0.5 + Rect2(body_image.get_used_rect()).get_center()
	_build_animation()
	_update_placement()


func _shared_frames() -> SpriteFrames:
	var cache_key: StringName = &"booster_warning_frames" if combat_warning else &"booster_exclamation_frames"
	if get_tree().has_meta(cache_key):
		return get_tree().get_meta(cache_key) as SpriteFrames
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_loop(&"idle", true)
	frames.set_animation_speed(&"idle", 8.0)
	var path: String = WARNING_PATH if combat_warning else FRAME_PATH
	for index: int in range(1, 10 if combat_warning else 9):
		var source: Texture2D = load(path % index) as Texture2D
		if source.get_size() != Vector2(NATIVE_SIZE, NATIVE_SIZE):
			var pixels: Image = source.get_image()
			if pixels.is_compressed():
				pixels.decompress()
			pixels.resize(NATIVE_SIZE, NATIVE_SIZE, Image.INTERPOLATE_NEAREST)
			source = ImageTexture.create_from_image(pixels)
		frames.add_frame(&"idle", source)
	get_tree().set_meta(cache_key, frames)
	return frames


func _build_animation() -> void:
	var frames: SpriteFrames = _shared_frames()
	for index: int in range(frames.get_frame_count(&"idle")):
		_glow_frames.append(OUTER_GLOW.texture_for(frames.get_frame_texture(&"idle", index)))
	_glow = Sprite2D.new()
	_glow.name = "WarningGlow" if combat_warning else "ExclamationGlow"
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow.material = additive
	_glow.scale = Vector2.ONE * DISPLAY_SIZE / float(NATIVE_SIZE)
	add_child(_glow)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Warning" if combat_warning else "Exclamation"
	_sprite.sprite_frames = frames
	_sprite.scale = Vector2.ONE * DISPLAY_SIZE / float(NATIVE_SIZE)
	if not combat_warning:
		var palette_material: ShaderMaterial = ShaderMaterial.new()
		palette_material.shader = PALETTE
		palette_material.set_shader_parameter("shadow_orange", Color("#cc781b"))
		palette_material.set_shader_parameter("golden_yellow", Color("#ffd448"))
		palette_material.set_shader_parameter("bright_yellow", Color("#ffe983"))
		palette_material.set_shader_parameter("highlight", Color("#fff8d6"))
		_sprite.material = palette_material
	add_child(_sprite)
	_sprite.frame_changed.connect(_update_glow_frame)
	_sprite.play(&"idle")
	_update_glow_frame()
	_light = PointLight2D.new()
	_light.name = "WarningLight" if combat_warning else "YellowLight"
	_light.texture = LIGHT_TEXTURE
	_light.texture_scale = 0.9
	_light.position = Vector2(0, 8)
	_light.color = Color("#ff924a") if combat_warning else Color("#ffcb4c")
	_light.energy = 0.2
	_light.shadow_enabled = false
	add_child(_light)


func set_active(active: bool) -> void:
	if visible == active:
		return
	visible = active
	set_process(active)
	_light.enabled = active
	if active:
		_sprite.play(&"idle")
		_update_placement()
	else:
		_sprite.pause()


func _update_glow_frame() -> void:
	_glow.texture = _glow_frames[_sprite.frame]


func _process(delta: float) -> void:
	_elapsed += delta
	_update_placement()
	var breathe: float = 0.9 + sin(_elapsed * 2.2) * 0.1
	_glow.modulate = Color(_light.color, 0.42 * breathe)
	_light.energy = 0.2 * breathe


func _update_placement() -> void:
	var parent_visuals: Node2D = get_parent() as Node2D
	var inherited_scale: Vector2 = parent_visuals.global_scale.abs()
	scale = Vector2.ONE / inherited_scale
	var tick: float = floorf(_elapsed * 12.0) / 12.0
	var bob: float = roundf(sin(tick * TAU / 1.8) * 2.0)
	position = _anchor + Vector2(0, (-HEIGHT_ABOVE_BODY + bob) / inherited_scale.y)
