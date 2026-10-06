extends Range
## Authored 288 x 32 ornament, clipped on red pixels only; immediate health truth.
const ART: Texture2D = preload("res://assets/effects/boss life bar/Asterion.png")
const BAR_SHADER: Shader = preload("res://shaders/boss_life_bar.gdshader")
var damage_ratio: float = 1.0
var hold_time: float = 0.0
var initialized: bool = false
var bar_material: ShaderMaterial

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_material = ShaderMaterial.new()
	bar_material.shader = BAR_SHADER
	material = bar_material
	value_changed.connect(_on_value_changed)
	_on_value_changed(value)
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(ART, Rect2(Vector2.ZERO, size), false)

func _on_value_changed(_current: float) -> void:
	if bar_material == null:
		return
	var health_fraction: float = clampf((value - min_value) / maxf(0.001, max_value - min_value), 0.0, 1.0)
	if not initialized or health_fraction >= damage_ratio:
		damage_ratio = health_fraction
		initialized = true
	else:
		hold_time = 0.18
	bar_material.set_shader_parameter("health_ratio", health_fraction)
	bar_material.set_shader_parameter("damage_ratio", damage_ratio)

func _process(delta: float) -> void:
	var health_fraction: float = clampf((value - min_value) / maxf(0.001, max_value - min_value), 0.0, 1.0)
	hold_time = maxf(0.0, hold_time - delta)
	if hold_time <= 0.0:
		damage_ratio = move_toward(damage_ratio, health_fraction, delta * 1.2)
	bar_material.set_shader_parameter("damage_ratio", damage_ratio)
