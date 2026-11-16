extends AnimatedSprite2D
signal death_finished
const PALETTE: Script = preload("res://scripts/visual/biome_enemy_palette.gd")
var floor_height: float = 0.0
var jump_height: float = 0.0
var _dying: bool = false
var _flash_left: float = 0.0
var _hit_left: float = 0.0
var _palette: ShaderMaterial = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_frames = preload("res://resources/enemies/slime/frames.tres")
	offset = Vector2(0, -7) # Fixed feet pivot: (16,23), including the final puddle.
	_palette = PALETTE.material_for(&"slime")
	material = _palette
	animation_finished.connect(_on_animation_finished)
	play(&"idle")
	position.y = -floor_height


func update_pose(attack_frame: int, direction: Vector2, speed: float) -> void:
	if _dying: return
	position.y = -floor_height - jump_height
	if absf(direction.x) > 0.05: flip_h = direction.x < 0.0
	if attack_frame >= 0:
		animation = &"attack"
		pause()
		set_frame_and_progress(clampi(attack_frame, 0, 11), 0.0)
	elif _hit_left > 0.0:
		if animation != &"hit" or not is_playing(): play(&"hit")
	else:
		if animation != &"idle" or not is_playing(): play(&"idle")
		speed_scale = 1.25 if speed > 5.0 else 0.75


func flash_hit() -> void:
	_flash_left = 0.12
	_hit_left = 0.14


func begin_death() -> void:
	if _dying: return
	_dying = true
	jump_height = 0.0
	position.y = -floor_height
	_palette.set_shader_parameter(&"flash_amount", 0.0)
	speed_scale = 1.0
	play(&"death")


func _process(delta: float) -> void:
	if _dying: return
	_flash_left = maxf(_flash_left - delta, 0.0)
	_hit_left = maxf(_hit_left - delta, 0.0)
	_palette.set_shader_parameter(&"flash_amount", _flash_left / 0.12)


func _on_animation_finished() -> void:
	if _dying and animation == &"death": death_finished.emit()
