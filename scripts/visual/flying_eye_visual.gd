extends Sprite2D
## Native art, 16 px body, vertical hover and per-shot recoil. No physics writes.
signal death_finished

const POSES: Dictionary[StringName, Texture2D] = {
	&"idle": preload("res://assets/enemies/flying eye/idle.png"),
	&"attack1": preload("res://assets/enemies/flying eye/attack1.png"),
	&"attack2": preload("res://assets/enemies/flying eye/attack2.png"),
	&"back_left": preload("res://assets/enemies/flying eye/back_looking_left.png"),
	&"back_right": preload("res://assets/enemies/flying eye/back_lookin_right.png"),
}
const DEATH: Array[Texture2D] = [
	preload("res://assets/enemies/flying eye/death_01.png"), preload("res://assets/enemies/flying eye/death_02.png"),
	preload("res://assets/enemies/flying eye/death_03.png"), preload("res://assets/enemies/flying eye/death_04.png"),
	preload("res://assets/enemies/flying eye/death_05.png"), preload("res://assets/enemies/flying eye/death_06.png"),
	preload("res://assets/enemies/flying eye/death_07.png"), preload("res://assets/enemies/flying eye/death_08.png"),
	preload("res://assets/enemies/flying eye/death_09.png"), preload("res://assets/enemies/flying eye/death_10.png"),
]
static var _cropped: Dictionary[StringName, AtlasTexture] = {}
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
var _death_age: float = 0.0
var _death_origin: Vector2 = Vector2.ZERO
var _flash: float = 0.0
var _flash_material: ShaderMaterial = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for key: StringName in POSES:
		if _cropped.has(key): continue
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = POSES[key]
		atlas.region = Rect2(POSES[key].get_image().get_used_rect())
		_cropped[key] = atlas
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = preload("res://shaders/white_damage_flash.gdshader")
	material = _flash_material
	_set_pose(&"idle")
	_update_visual(0.0)


func _set_pose(pose: StringName) -> void:
	texture = _cropped[pose]
	scale = Vector2.ONE * (16.0 / maxf(texture.get_width(), texture.get_height()))
	offset = Vector2.ZERO
	flip_h = pose not in [&"back_left", &"back_right"] and look_direction.x < -0.05


func flash_hit() -> void:
	_flash = 0.7


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
	_death_origin = position
	preparing = false
	_flash = 0.0
	_flash_material.set_shader_parameter(&"flash_amount", 0.0)
	flip_h = false
	texture = DEATH[0]
	scale = Vector2.ONE * (16.0 / 52.0)
	# Same (48,37) pivot in all ten 96x80 canvases, never recenter particles.
	offset = Vector2(0, 3)


func _process(delta: float) -> void:
	_update_visual(delta)


func _update_visual(delta: float) -> void:
	if dying:
		_death_age += delta
		var death_frame: int = floori(_death_age * 16.0)
		if death_frame >= DEATH.size():
			set_process(false)
			death_finished.emit()
			return
		texture = DEATH[death_frame]
		position = _death_origin
		return
	_age += delta
	_recoil_left = maxf(_recoil_left - delta, 0.0)
	_flash = maxf(_flash - delta * 8.0, 0.0)
	_flash_material.set_shader_parameter(&"flash_amount", _flash)
	hover_offset = sin(_age * TAU / 2.2 + phase) * 1.25
	recoil_offset = _recoil_direction * 2.4 * pow(_recoil_left / 0.14, 2.0)
	position = Vector2(0, -8.0 - floor_height + hover_offset) + recoil_offset
	var pose: StringName = &"attack2" if _recoil_left > 0.015 else &"attack1" if preparing else &"idle"
	if not preparing and _recoil_left <= 0.0 and look_direction.y < -0.35:
		pose = &"back_left" if look_direction.x < 0.0 else &"back_right"
	_set_pose(pose)
