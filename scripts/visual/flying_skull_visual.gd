extends Sprite2D
signal death_finished
const FRAMES: SpriteFrames = preload("res://resources/enemies/flying_skull/frames.tres")
const PALETTE: Script = preload("res://scripts/visual/biome_enemy_palette.gd")
var floor_height: float = 0.0
var phase: float = 0.0
var look_direction: Vector2 = Vector2.RIGHT
var preparing: bool = false
var dying: bool = false
var recoil_count: int = 0
var hover_offset: float = 0.0
var recoil_offset: Vector2 = Vector2.ZERO
var _age: float = 0.0
var _recoil_left: float = 0.0
var _recoil_direction: Vector2 = Vector2.ZERO
var _hit_left: float = 0.0
var _death_age: float = 0.0
var _flash_material: ShaderMaterial = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2.ONE * 0.72
	_flash_material = PALETTE.material_for(&"flying_skull")
	material = _flash_material
	_update_visual(0.0)


func flash_hit() -> void:
	_hit_left = 0.14


func shot_recoil(direction: Vector2) -> void:
	if dying: return
	look_direction = direction.normalized()
	_recoil_direction = -look_direction
	_recoil_left = 0.14
	recoil_count += 1


func begin_death() -> void:
	if dying: return
	dying = true
	_death_age = 0.0
	preparing = false
	_flash_material.set_shader_parameter(&"flash_amount", 0.0)


func _process(delta: float) -> void:
	_update_visual(delta)


func _update_visual(delta: float) -> void:
	if dying:
		_death_age += delta
		var death_pose: int = floori(_death_age * 14.0)
		if death_pose >= FRAMES.get_frame_count(&"death"):
			set_process(false)
			death_finished.emit()
			return
		texture = FRAMES.get_frame_texture(&"death", death_pose)
		return
	_age += delta
	_recoil_left = maxf(_recoil_left - delta, 0.0)
	_hit_left = maxf(_hit_left - delta, 0.0)
	_flash_material.set_shader_parameter(&"flash_amount", _hit_left / 0.14 * 0.7)
	hover_offset = sin(_age * TAU / 2.2 + phase) * 1.25
	recoil_offset = _recoil_direction * 2.4 * pow(_recoil_left / 0.14, 2.0)
	position = Vector2(0, -8.0 - floor_height + hover_offset) + recoil_offset
	flip_h = look_direction.x < -0.05
	var clip: StringName = &"attack" if preparing or _recoil_left > 0.0 else &"hit" if _hit_left > 0.0 else &"idle"
	var pose: int = floori(_age * 12.0) % FRAMES.get_frame_count(clip)
	if clip == &"attack": pose = clampi(floori((0.14 - _recoil_left) / 0.14 * 3.0) + 3, 3, 5) if _recoil_left > 0.0 else floori(_age * 10.0) % 3
	texture = FRAMES.get_frame_texture(clip, pose)
