extends CanvasLayer
## One screen-space graphic cut. The player can recoil away from its fixed origin.

const DIRECTIONS: Array[float] = [PI / 4.0, PI / 2.0, PI * 3.0 / 4.0]
const SWEEP_DURATION: float = 0.035
const RELEASE_DURATION: float = 0.15
const WIDTH_RATIO: float = 0.027

var elapsed: float = 0.0
var impact_pause: float = 0.045
var origin_ratio: Vector2 = Vector2(0.5, 0.5)
var slash_angle: float = PI / 4.0
var flash: Polygon2D
var contrast: Polygon2D
var slash: Polygon2D


func configure(viewport_size: Vector2, screen_origin: Vector2, pause_duration: float) -> void:
	origin_ratio = (screen_origin / viewport_size).clamp(Vector2.ZERO, Vector2.ONE)
	impact_pause = maxf(pause_duration, SWEEP_DURATION)
	slash_angle = DIRECTIONS[randi_range(0, DIRECTIONS.size() - 1)]


func _ready() -> void:
	name = "ParryGraphicSlash"
	layer = 80
	add_to_group(&"parry_effects")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	contrast = Polygon2D.new()
	contrast.name = "ImpactContrast"
	add_child(contrast)
	flash = Polygon2D.new()
	flash.name = "ImpactFlash"
	add_child(flash)
	slash = Polygon2D.new()
	slash.name = "WhiteSlash"
	slash.color = Color.WHITE
	add_child(slash)
	_update_visual()


func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed >= impact_pause + RELEASE_DURATION:
		queue_free()
		return
	_update_visual()


func _update_visual() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var centre: Vector2 = viewport_size * origin_ratio
	var screen_rect: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)])
	flash.polygon = screen_rect
	contrast.polygon = screen_rect
	# A brief white exposure, then a low contrast pulse behind the white pose/slash.
	flash.color = Color(1.0, 1.0, 1.0, 0.10 * pow(1.0 - clampf(elapsed / impact_pause, 0.0, 1.0), 2.0))
	var release: float = clampf((elapsed - impact_pause) / RELEASE_DURATION, 0.0, 1.0)
	contrast.color = Color(0.08, 0.035, 0.06, 0.12 * sin(release * PI))
	var direction: Vector2 = Vector2.from_angle(slash_angle)
	# Extend beyond both viewport edges, even when the player is off-centre.
	var before: float = _edge_distance(centre, -direction, viewport_size) + 16.0
	var after: float = _edge_distance(centre, direction, viewport_size) + 16.0
	var sweep: float = 0.24 + 0.76 * (1.0 - pow(1.0 - clampf(elapsed / SWEEP_DURATION, 0.0, 1.0), 3.0))
	var tail: float = -before * sweep
	var tip: float = after * sweep
	var width: float = minf(viewport_size.x, viewport_size.y) * WIDTH_RATIO * (1.0 - release) * (1.0 - release)
	slash.position = centre
	slash.rotation = slash_angle
	# Tapered, asymmetric blade silhouette, not a stretched lightning sprite.
	slash.polygon = PackedVector2Array([
		Vector2(tail, 0.0), Vector2(tail * 0.40, -width * 0.32),
		Vector2(-3.0, -width * 0.65), Vector2(tip * 0.62, -width * 0.30),
		Vector2(tip, 0.0), Vector2(tip * 0.38, width * 0.10),
		Vector2(3.0, width * 0.40), Vector2(tail * 0.55, width * 0.18)
	])
	slash.color.a = 1.0 - release


func _edge_distance(centre: Vector2, direction: Vector2, viewport_size: Vector2) -> float:
	var distance: float = INF
	if absf(direction.x) > 0.001:
		distance = minf(distance, ((viewport_size.x if direction.x > 0.0 else 0.0) - centre.x) / direction.x)
	if absf(direction.y) > 0.001:
		distance = minf(distance, ((viewport_size.y if direction.y > 0.0 else 0.0) - centre.y) / direction.y)
	return maxf(distance, 0.0)
