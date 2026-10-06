extends Range
## Six authored ten-HP blocks. Presentation only: the Player still owns health.
const EMPTY: Texture2D = preload("res://assets/characters/player/life bar/empty.png")
const FILL_SHADER: Shader = preload("res://shaders/player_life_bar.gdshader")
const STABLE: Array[Texture2D] = [
	EMPTY,
	preload("res://assets/characters/player/life bar/Sprite-0023.png"),
	preload("res://assets/characters/player/life bar/Sprite-0021.png"),
	preload("res://assets/characters/player/life bar/Sprite-0019.png"),
	preload("res://assets/characters/player/life bar/Sprite-0017.png"),
	preload("res://assets/characters/player/life bar/Sprite-0015.png"),
	preload("res://assets/characters/player/life bar/Sprite-0013.png"),
]
const DAMAGE: Array[Texture2D] = [
	preload("res://assets/characters/player/life bar/Sprite-0024.png"),
	preload("res://assets/characters/player/life bar/Sprite-0022.png"),
	preload("res://assets/characters/player/life bar/Sprite-0020.png"),
	preload("res://assets/characters/player/life bar/Sprite-0018.png"),
	preload("res://assets/characters/player/life bar/Sprite-0016.png"),
	preload("res://assets/characters/player/life bar/Sprite-0014.png"),
]
const ART_REGION: Rect2 = Rect2(14, 3, 68, 10)
const BLOCK_STARTS: Array[int] = [16, 26, 38, 48, 59, 71]
const BLOCK_WIDTHS: Array[int] = [8, 9, 9, 9, 10, 10]
const FLASH_DURATION: float = 0.36
const FLASH_STEP: float = 0.06

var lit_blocks: int = 6
var flash_mask: int = 0
var flash_remaining: float = 0.0
var flash_visible: bool = false
var initialized: bool = false
var previous_value: float = 0.0
var fill_material: ShaderMaterial

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_material = ShaderMaterial.new()
	fill_material.shader = FILL_SHADER
	material = fill_material
	value_changed.connect(_on_health_changed)
	_on_health_changed(value)

func _on_health_changed(current: float) -> void:
	var health_blocks: float = clampf((current - min_value) / maxf(max_value - min_value, 0.001), 0.0, 1.0) * 6.0
	var next_blocks: int = clampi(ceili(health_blocks - 0.000001), 0, 6)
	if initialized and current < previous_value and next_blocks < lit_blocks:
		# Large hits mark every crossed block, not just the final one.
		for block_index: int in range(next_blocks, lit_blocks):
			flash_mask |= 1 << block_index
		flash_remaining = FLASH_DURATION
		flash_visible = true
	elif initialized and current > previous_value:
		# Healing must never leave a red damage frame over replenished health.
		flash_mask = 0
		flash_remaining = 0.0
		flash_visible = false
	lit_blocks = next_blocks
	previous_value = current
	initialized = true
	fill_material.set_shader_parameter(&"health_blocks", health_blocks)
	queue_redraw()

func _process(delta: float) -> void:
	if flash_remaining <= 0.0:
		return
	flash_remaining = maxf(0.0, flash_remaining - delta)
	flash_visible = flash_remaining > 0.0 and int((FLASH_DURATION - flash_remaining) / FLASH_STEP) % 2 == 0
	if flash_remaining <= 0.0:
		flash_mask = 0
	queue_redraw()

func _draw() -> void:
	var destination: Rect2 = Rect2(Vector2.ZERO, size)
	draw_texture_rect_region(EMPTY, destination, ART_REGION)
	if lit_blocks > 0:
		draw_texture_rect_region(STABLE[lit_blocks], destination, ART_REGION)
	if not flash_visible:
		return
	for block_index: int in range(6):
		if (flash_mask & (1 << block_index)) == 0:
			continue
		var source: Rect2 = Rect2(BLOCK_STARTS[block_index], 3, BLOCK_WIDTHS[block_index], 10)
		var red_destination: Rect2 = Rect2(
			Vector2((source.position.x - ART_REGION.position.x) / ART_REGION.size.x * size.x, 0),
			Vector2(source.size.x / ART_REGION.size.x * size.x, size.y)
		)
		draw_texture_rect_region(DAMAGE[block_index], red_destination, source)
