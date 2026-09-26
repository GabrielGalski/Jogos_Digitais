@tool
extends Node2D
## LED confined to the external pink/white frame, with no glow on the lettering.

@export var led_color: Color = Color("ff469c")


func _draw() -> void:
	var border: Rect2 = Rect2(4.5, 1.5, 196.0, 43.0)
	# The opaque sign face covers the inner half of these soft outlines.
	draw_rect(border, Color(led_color, 0.035), false, 12.0)
	draw_rect(border, Color(led_color, 0.065), false, 8.0)
	draw_rect(border, Color(led_color, 0.12), false, 4.0)
