class_name PackSlashController
extends RefCounted
## A held stroke can start anywhere; only a continuous crossing of the seal cuts.

var active: bool = false
var completed: bool = false
var entered: bool = false
var progress: float = 0.0
var direction: float = 1.0
var coverage: float = 0.85
var tolerance: float = 9.0
var seal: Rect2 = Rect2()
var start_x: float = 0.0
var tip: Vector2 = Vector2.ZERO
var previous: Vector2 = Vector2.ZERO
var view_to_seal: Transform2D = Transform2D.IDENTITY


func begin(pointer: Vector2, seal_rect: Rect2, required_coverage: float, margin: float, seal_to_view: Transform2D = Transform2D.IDENTITY) -> bool:
	reset()
	seal = seal_rect
	coverage = clampf(required_coverage, 0.6, 1.0)
	tolerance = maxf(margin, 1.0)
	view_to_seal = seal_to_view.affine_inverse()
	previous = view_to_seal * pointer
	tip = pointer
	active = seal.size.x > 0.0
	return active


func advance(pointer: Vector2) -> bool:
	if not active or completed:
		return false
	var current: Vector2 = view_to_seal * pointer
	var from: Vector2 = previous
	previous = current
	tip = pointer
	var band: Rect2 = seal.grow_individual(0.0, tolerance, 0.0, tolerance)
	var interval: Vector2 = _clip_segment(from, current, band)
	if interval.x < 0.0:
		entered = false
		progress = 0.0
		return false
	var entry: Vector2 = from.lerp(current, interval.x)
	if not entered:
		var fraction: float = (entry.x - seal.position.x) / seal.size.x
		var edge_fraction: float = 1.0 - coverage
		if fraction > edge_fraction and fraction < 1.0 - edge_fraction:
			return false
		direction = 1.0 if fraction <= 0.5 else -1.0
		if (current.x - from.x) * direction <= 0.0:
			return false
		start_x = entry.x
		entered = true
	var end: Vector2 = from.lerp(current, interval.y)
	# Clip the entire segment: a fast swipe may skip the sprite between events.
	progress = clampf((end.x - start_x) * direction / maxf(seal.size.x * coverage, 1.0), 0.0, 1.0)
	if progress >= 1.0:
		completed = true
		active = false
		return true
	if interval.y < 1.0:
		entered = false
		progress = 0.0
	return false


func _clip_segment(from: Vector2, to: Vector2, rect: Rect2) -> Vector2:
	var delta: Vector2 = to - from
	var first: float = 0.0
	var last: float = 1.0
	for axis: int in range(2):
		if absf(delta[axis]) < 0.00001:
			if from[axis] < rect.position[axis] or from[axis] > rect.end[axis]:
				return Vector2(-1.0, -1.0)
			continue
		var a: float = (rect.position[axis] - from[axis]) / delta[axis]
		var b: float = (rect.end[axis] - from[axis]) / delta[axis]
		first = maxf(first, minf(a, b))
		last = minf(last, maxf(a, b))
		if first > last:
			return Vector2(-1.0, -1.0)
	return Vector2(first, last)


func release() -> void:
	if not completed:
		reset()


func reset() -> void:
	active = false
	completed = false
	entered = false
	progress = 0.0
	direction = 1.0
