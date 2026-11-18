extends Node2D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventMouse:
		var viewer_transform: Transform2D = (get_parent() as CanvasItem).get_global_transform_with_canvas()
		position = (viewer_transform.affine_inverse() * event.position).round()


func _draw() -> void:
	var outline: Color = Color("#24132e")
	var tint: Color = Color("#eee0e8")
	draw_rect(Rect2(-4, -1, 9, 3), outline)
	draw_rect(Rect2(-1, -4, 3, 9), outline)
	draw_rect(Rect2(-3, 0, 7, 1), tint)
	draw_rect(Rect2(0, -3, 1, 7), tint)
