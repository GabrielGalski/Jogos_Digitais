extends Node2D
## Shared moving one-pixel arcs, sized to the warp or the pedestal's central circle.
var radius: Vector2 = Vector2(12, 12)
var _time: float = 0.0
var _frame: int = -1
var _points: Array[Vector2i] = []
var _angles: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var unshaded: CanvasItemMaterial = CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded
	if _points.is_empty():
		_rebuild_path()


func configure(radii: Vector2, center: Vector2 = Vector2.ZERO) -> void:
	radius = radii.round().max(Vector2.ONE)
	position = center.round()
	_rebuild_path()
	queue_redraw()


func _rebuild_path() -> void:
	_points.clear()
	_angles.clear()
	var seen: Dictionary[Vector2i, bool] = {}
	var samples: int = maxi(64, ceili(TAU * maxf(radius.x, radius.y) * 2.0))
	for index: int in range(samples):
		var point: Vector2i = Vector2i((Vector2.from_angle(TAU * float(index) / float(samples)) * radius).round())
		if seen.has(point):
			continue
		seen[point] = true
		_points.append(point)
		_angles.append(Vector2(point).angle())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	var next_frame: int = int(_time * 12.0)
	if next_frame != _frame:
		_frame = next_frame
		queue_redraw()


func _draw() -> void:
	var rotation_step: float = float(_frame) * TAU / 40.0
	for index: int in range(_points.size()):
		var trail: float = fposmod(_angles[index] - rotation_step, PI) / PI
		if trail > 0.66:
			continue
		draw_rect(Rect2(Vector2(_points[index]), Vector2.ONE), Color(1.0, 0.98, 1.0, 0.35 + 0.65 * (1.0 - trail / 0.66)))
