extends Node2D
## Authored finisher sprite, rendered behind the dying actor, never over the HUD.

const COLOR: Color = Color("#8157c6")
const DURATION: float = 0.14
const SWEEP_DURATION: float = 0.025
const WHITE_HOLD: float = 0.035
const FINISHER: Texture2D = preload("res://assets/effects/finisher/effect.png")
const OUTER_GLOW: Script = preload("res://scripts/visual/sprite_outer_glow.gd")
const FLASH_SHADER: Shader = preload("res://shaders/enemy_finishing_flash.gdshader")
const LIGHT_RIG: Script = preload("res://scripts/visual/arena_lighting_rig.gd")
const ONCE: StringName = &"enemy_finishing_ray_played"

var source: Node2D = null
var local_center: Vector2 = Vector2.ZERO
var length: float = 96.0
var sprite_scale: float = 1.0
var elapsed: float = 0.0
var core: Sprite2D = null
var glow: Sprite2D = null
var light: PointLight2D = null
var flash_material: ShaderMaterial = null
var previous_material: Material = null


static func play(enemy: Node2D, visual: Node2D) -> Node2D:
	if not is_instance_valid(enemy) or not is_instance_valid(visual) or enemy.has_meta(ONCE):
		return null
	var texture: Texture2D = _texture_of(visual)
	if texture == null:
		return null
	enemy.set_meta(ONCE, true)
	var effect_script: Script = load("res://scripts/combat/effects/enemy_finishing_ray.gd") as Script
	var effect: Node2D = effect_script.new() as Node2D
	effect.call("configure", visual, texture)
	var world: Node = enemy.get_tree().current_scene
	if not is_instance_valid(world):
		world = enemy.get_parent()
	world.add_child(effect)
	return effect


static func _texture_of(visual: Node2D) -> Texture2D:
	var animated: AnimatedSprite2D = visual as AnimatedSprite2D
	if animated != null:
		return animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
	var sprite: Sprite2D = visual as Sprite2D
	return sprite.texture if sprite != null else null


func configure(visual: Node2D, texture: Texture2D) -> void:
	source = visual
	var pixels: Image = texture.get_image()
	if pixels != null and pixels.is_compressed():
		pixels.decompress()
	var bounds: Rect2 = Rect2(pixels.get_used_rect()) if pixels != null else Rect2(Vector2.ZERO, texture.get_size())
	local_center = bounds.get_center()
	if bool(source.get("flip_h")):
		local_center.x = texture.get_width() - local_center.x
	if bool(source.get("flip_v")):
		local_center.y = texture.get_height() - local_center.y
	if bool(source.get("centered")):
		local_center -= texture.get_size() * 0.5
	local_center += source.get("offset") as Vector2
	var dimensions: Vector2 = bounds.size * source.global_scale.abs()
	length = clampf(maxf(dimensions.x, dimensions.y) * 3.4, 64.0, 170.0)
	# Resolve the full canvas depth, including absolute-Z actors and the boss proxy.
	var depth: int = 0
	var cursor: Node2D = source
	while cursor != null:
		depth += cursor.z_index
		if not cursor.z_as_relative:
			break
		cursor = cursor.get_parent() as Node2D
	z_as_relative = false
	z_index = depth - 1
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 20
	previous_material = source.material
	flash_material = ShaderMaterial.new()
	flash_material.shader = FLASH_SHADER
	source.material = flash_material


func _ready() -> void:
	name = "EnemyFinishingRay"
	top_level = true
	global_transform = Transform2D.IDENTITY
	add_to_group(&"enemy_finishing_rays")
	var asset_bounds: Rect2 = Rect2(FINISHER.get_image().get_used_rect())
	# Diagonal is authored in the PNG: no second rotation, no color replacement.
	sprite_scale = length / maxf(asset_bounds.size.length(), 1.0)
	var anchor: Vector2 = FINISHER.get_size() * 0.5 - asset_bounds.get_center()
	core = Sprite2D.new()
	core.name = "VioletCut"
	core.texture = FINISHER
	core.offset = anchor
	core.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var opaque: CanvasItemMaterial = CanvasItemMaterial.new()
	opaque.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	core.material = opaque
	add_child(core)
	glow = Sprite2D.new()
	glow.name = "SoftGlow"
	glow.z_index = -1
	glow.texture = OUTER_GLOW.texture_for(FINISHER)
	glow.offset = anchor
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var bloom: CanvasItemMaterial = CanvasItemMaterial.new()
	bloom.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	bloom.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = bloom
	add_child(glow)
	light = PointLight2D.new()
	light.name = "KillPulse"
	light.texture = LIGHT_RIG.make_radial_texture()
	light.texture_scale = clampf(length * 0.2 / 64.0, 0.20, 0.45)
	light.color = COLOR
	light.shadow_enabled = false
	light.range_z_min = -2
	light.range_z_max = 2
	add_child(light)
	_update_visual()


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= DURATION:
		_restore_material()
		queue_free()
		return
	_update_visual()


func _update_visual() -> void:
	if is_instance_valid(source):
		global_position = source.to_global(local_center)
		flash_material.set_shader_parameter(&"flash_amount", 1.0 - smoothstep(WHITE_HOLD, DURATION, elapsed))
	var release: float = clampf((elapsed - WHITE_HOLD) / (DURATION - WHITE_HOLD), 0.0, 1.0)
	var opacity: float = (1.0 - release) * (1.0 - release)
	var sweep: float = 0.18 + 0.82 * (1.0 - pow(1.0 - clampf(elapsed / SWEEP_DURATION, 0.0, 1.0), 3.0))
	core.scale = Vector2.ONE * sprite_scale * sweep
	core.modulate = Color(1.0, 1.0, 1.0, opacity)
	glow.scale = core.scale
	glow.modulate = Color(COLOR, opacity * 0.65)
	light.energy = opacity * 0.32


func _restore_material() -> void:
	if is_instance_valid(source) and source.material == flash_material:
		source.material = previous_material


func _exit_tree() -> void:
	_restore_material()
