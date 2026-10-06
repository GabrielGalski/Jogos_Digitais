extends Sprite2D
## The four existing UI/aim frames form the screen-space manifestation reticle.

const FRAMES: Array[Texture2D] = [
	preload("res://assets/UI/aim/aim1.png"),
	preload("res://assets/UI/aim/aim2.png"),
	preload("res://assets/UI/aim/aim3.png"),
	preload("res://assets/UI/aim/aim4.png"),
]

var tint: Color = Color("#a8e387")
var elapsed: float = 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	scale = Vector2.ONE * 0.5
	texture = FRAMES[0]
	modulate = tint
	position = get_viewport().get_mouse_position().round()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		position = event.position.round()


func _process(delta: float) -> void:
	elapsed += delta
	texture = FRAMES[int(elapsed * 8.0) % FRAMES.size()]


func set_tint(value: Color) -> void:
	tint = value
	modulate = value
