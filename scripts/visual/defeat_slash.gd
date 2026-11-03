extends Node2D
## One tapered diagonal stroke, sampled on whole pixels at the game's resolution.

var progress: float = -1.0
var pixel_scale: float = 1.0


func _draw() -> void:
	if progress < 0.0 or progress > 1.0:
		return
	var tip: float = minf(progress / 0.35, 1.0)
	var tail: float = maxf((progress - 0.3) / 0.7, 0.0)
	var unit: float = maxf(1.0, roundf(pixel_scale))
	for index: int in range(65):
		var along: float = float(index) / 64.0
		if along < tail or along > tip:
			continue
		var thickness: float = ceilf(sin(along * PI) * 3.0 * (1.0 - progress * 0.55))
		var point: Vector2 = Vector2(-32.0 + index, -32.0 + index) * unit
		var extent: Vector2 = Vector2.ONE * maxf(1.0, thickness) * unit
		draw_rect(Rect2(point - (extent * 0.5).floor(), extent), Color.WHITE)
