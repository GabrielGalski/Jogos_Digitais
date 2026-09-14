extends Node2D
## Short ground pulse for the preview; no persistent target marker.
var remaining := 0.0
var radius := 40.0

func start(value: float) -> void:
	radius = value
	remaining = 0.35
	queue_redraw()

func _process(delta: float) -> void:
	if remaining > 0.0:
		remaining = maxf(0.0, remaining - delta)
		queue_redraw()

func _draw() -> void:
	if remaining <= 0.0:
		return
	var t := 1.0 - remaining / 0.35
	draw_arc(Vector2.ZERO, radius * lerpf(0.25, 1.0, t), 0, TAU, 48, Color(0.9, 0.65, 0.35, (1.0 - t) * 0.85), 1.5)
	for i in range(12):
		var direction := Vector2.from_angle(TAU * i / 12.0)
		var p := direction * radius * t
		draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(0.55, 0.32, 0.35, 1.0 - t))
