extends Node2D
## Fine luminous sparks and a fading shock ring; presentation only.

var model: ProceduralManifestationModel
var radius: float = 8.0
var duration: float = 0.18
var age: float = 0.0
var direction: Vector2 = Vector2.RIGHT


func configure(definition: ProceduralManifestationModel, size: float, aim: Vector2 = Vector2.RIGHT) -> void:
	model = definition
	radius = maxf(size, 4.0)
	duration = 0.24 if radius > 15.0 else 0.14
	direction = aim
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var opaque: CanvasItemMaterial = CanvasItemMaterial.new()
	opaque.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = opaque


func _process(delta: float) -> void:
	age += delta
	if age >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if model == null:
		return
	var progress: float = clampf(age / duration, 0.0, 1.0)
	var expanded: float = lerpf(2.0, radius, sqrt(progress))
	var opacity: float = (1.0 - progress) * (1.0 - progress)
	if radius > 15.0 and progress < 0.78:
		var points: PackedVector2Array = PackedVector2Array()
		for index: int in range(65):
			points.append(Vector2.from_angle(float(index) * TAU / 64.0) * expanded)
		draw_polyline(points, Color(model.body_color, opacity), 1.0, true)
		if progress < 0.35:
			draw_polyline(points, Color(model.core_color, opacity), 0.5, true)
	for index: int in range(7):
		var angle: float = float(index) * 2.39996 + direction.angle()
		var center: Vector2 = Vector2.from_angle(angle) * expanded * (0.55 + float(index % 3) * 0.15)
		var tail: Vector2 = center - Vector2.from_angle(angle) * lerpf(3.0, 0.5, progress)
		var tint: Color = model.core_color if index % 3 == 0 else model.body_color
		draw_line(tail, center, Color(tint, opacity), 0.8, true)
