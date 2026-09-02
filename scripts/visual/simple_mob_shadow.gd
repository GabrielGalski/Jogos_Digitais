extends Node2D
class_name SimpleMobShadow

@export var radius := 4.0
@export var color := Color(0.015, 0.006, 0.01, 0.16)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color, true, -1.0, false)
