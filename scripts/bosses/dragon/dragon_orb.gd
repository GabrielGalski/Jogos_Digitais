extends "res://scripts/combat/projectiles/flying_eye_orb.gd"

const EDGE: Color = Color("#7b234c")
var encounter_bounds: Rect2


func _ready() -> void:
	super._ready()
	remove_from_group(&"flying_eye_orbs")


func _physics_process(delta: float) -> void:
	if not encounter_bounds.has_point(global_position):
		dismiss()
		return
	super._physics_process(delta)


func _draw() -> void:
	var center: Vector2 = Vector2(0.0, -8.0 - _visual_height)
	var glow: Color = Color(0.86, 0.27, 0.55, 0.27) if not reflected else Color(1.0, 0.81, 0.45, 0.4)
	draw_circle(center, radius + 4.0, Color(glow, glow.a * 0.40), true, -1.0, true)
	draw_circle(center, radius + 2.0, glow, true, -1.0, true)
	draw_circle(center, radius + 0.4, EDGE, true, -1.0, true)
	draw_circle(center, radius * 0.61, Color.WHITE, true, -1.0, true)
