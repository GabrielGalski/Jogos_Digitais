extends Sprite2D
## Shared world-space E hint: white native pixels and a small vertical bob.
const ICON: Texture2D = preload("res://assets/UI/action.png")
var _anchor: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0


func _init() -> void:
	texture = ICON
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	z_index = 32
	visible = false
	var unshaded: CanvasItemMaterial = CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded


func _ready() -> void:
	set_process(visible)


func configure(anchor: Vector2) -> void:
	_anchor = anchor
	position = _anchor


func set_available(available: bool) -> void:
	if visible == available:
		return
	visible = available
	set_process(available)
	if not available:
		_elapsed = 0.0
		position = _anchor


func _process(delta: float) -> void:
	_elapsed += delta
	position = _anchor + Vector2(0, roundf(sin(_elapsed * TAU / 1.25) * 2.0))
