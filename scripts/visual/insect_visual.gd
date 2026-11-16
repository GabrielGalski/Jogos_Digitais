extends AnimatedSprite2D
## Fixed source pivot, native pixels. Attack poses are driven by the physics clock.
signal death_finished

const PALETTES: Script = preload("res://scripts/visual/insect_palettes.gd")
var floor_height: float = 0.0
var kind: StringName = &"little"
var palette_variant: int = 0
var look_direction: Vector2 = Vector2.RIGHT
var _flash_left: float = 0.0
var _hit_left: float = 0.0
var _dying: bool = false
var _flash_material: ShaderMaterial = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_frames = load("res://resources/enemies/insects/%s_frames.tres" % kind) as SpriteFrames
	offset = Vector2(0, -8) # 48x48 canvas, feet at (24,32), unchanged across poses.
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = PALETTES.SHADER
	material = _flash_material
	set_palette_variant(palette_variant)
	animation_finished.connect(_on_animation_finished)
	play(&"idle")
	position.y = -floor_height


func set_palette_variant(value: int) -> void:
	palette_variant = posmod(value, PALETTES.PROPOSALS.size())
	if _flash_material != null: PALETTES.apply(_flash_material, kind, palette_variant)


func update_pose(moving: bool, attacking: bool, age: float, settings: InsectProfile, direction: Vector2) -> void:
	if _dying: return
	look_direction = direction
	if absf(direction.x) > 0.05: flip_h = direction.x < 0.0
	position.y = -floor_height
	if attacking:
		if animation != &"attack": animation = &"attack"
		pause()
		var count: int = sprite_frames.get_frame_count(&"attack")
		var pose: int = 0
		if age < settings.windup:
			pose = mini(settings.impact_frame - 1, floori(age / settings.windup * settings.impact_frame))
		elif age < settings.windup + settings.active_duration:
			pose = settings.impact_frame
		else:
			var progress: float = clampf((age - settings.windup - settings.active_duration) / settings.recovery, 0.0, 0.999)
			pose = settings.impact_frame + 1 + floori(progress * (count - settings.impact_frame - 1))
		set_frame_and_progress(clampi(pose, 0, count - 1), 0.0)
	elif _hit_left > 0.0:
		if animation != &"hit" or not is_playing(): play(&"hit")
	else:
		var clip: StringName = &"walk" if moving and sprite_frames.has_animation(&"walk") else &"idle"
		if animation != clip or not is_playing(): play(clip)
		speed_scale = 1.25 if kind == &"fly" else 0.84 if kind == &"tall" else 1.0


func flash_hit() -> void:
	_flash_left = 0.12
	_hit_left = 0.16


func begin_death() -> void:
	if _dying: return
	_dying = true
	_flash_material.set_shader_parameter(&"flash_amount", 0.0)
	speed_scale = 1.0
	play(&"death")


func _process(delta: float) -> void:
	if _dying: return
	_flash_left = maxf(_flash_left - delta, 0.0)
	_hit_left = maxf(_hit_left - delta, 0.0)
	_flash_material.set_shader_parameter(&"flash_amount", _flash_left / 0.12)


func _on_animation_finished() -> void:
	if _dying and animation == &"death": death_finished.emit()
