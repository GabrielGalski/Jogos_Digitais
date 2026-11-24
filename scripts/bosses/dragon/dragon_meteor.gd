extends Node2D

const FALL: Array[Texture2D] = [
	preload("res://assets/enemies/dragon/meteor/meteor1.png"),
	preload("res://assets/enemies/dragon/meteor/meteor2.png"),
	preload("res://assets/enemies/dragon/meteor/meteor3.png"),
	preload("res://assets/enemies/dragon/meteor/meteor4.png"),
	preload("res://assets/enemies/dragon/meteor/meteor5.png"),
]
const IMPACT: Array[Texture2D] = [
	preload("res://assets/enemies/dragon/impact/impact1.png"),
	preload("res://assets/enemies/dragon/impact/impact2.png"),
	preload("res://assets/enemies/dragon/impact/impact3.png"),
]
const SHADOW = preload("res://scripts/visual/simple_mob_shadow.gd")
const WARNING: Script = preload("res://scripts/visual/booster_exclamation.gd")
const DAMAGE_RADIUS: float = 25.0
const IMPACT_FRAME_TIME: float = 0.105

var target: Player
var source: Node2D
var aimed: bool
var fall_time: float
var ground_height: float = 0.0
var allied_impact: Callable
var _age: float = 0.0
var _impacted: bool = false
var _shadow: SimpleMobShadow
var _warning: AnimatedSprite2D


func _ready() -> void:
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow = SHADOW.new()
	_shadow.radius = 11.0
	_shadow.position.y = -ground_height
	_shadow.show_behind_parent = true
	_shadow.scale = Vector2(0.66, 0.29)
	add_child(_shadow)
	if aimed and not allied_impact.is_valid():
		_warning = WARNING.warning_sprite(get_tree())
		_warning.position.y = -9.0 - ground_height
		add_child(_warning)
		_warning.play(&"idle")


func _physics_process(delta: float) -> void:
	_age += delta
	var progress: float = clampf(_age / fall_time, 0.0, 1.0)
	var intensity: float = 1.0 if aimed else 0.70
	_shadow.scale = Vector2(0.66, 0.29).lerp(Vector2(2.0, 0.90), progress) * intensity
	_shadow.modulate.a = lerpf(0.75, 1.0, progress)
	if not _impacted and _age >= fall_time:
		_impacted = true
		_shadow.hide()
		if _warning != null:
			_warning.hide()
			_warning.stop()
		if allied_impact.is_valid():
			allied_impact.call(global_position, DAMAGE_RADIUS)
		elif aimed and is_instance_valid(target) and not target.dead:
			if target.global_position.distance_squared_to(global_position) <= DAMAGE_RADIUS * DAMAGE_RADIUS:
				target.receive_projectile_damage(30, source)
	if _age >= fall_time + IMPACT_FRAME_TIME * IMPACT.size():
		dismiss()
	queue_redraw()


func dismiss() -> void:
	set_physics_process(false)
	queue_free()


func _draw() -> void:
	draw_set_transform(Vector2(0.0, -ground_height))
	if _impacted:
		var impact_frame: int = clampi(int((_age - fall_time) / IMPACT_FRAME_TIME), 0, IMPACT.size() - 1)
		var scale_factor: float = 0.68 if aimed else 0.44
		var impact_size: Vector2 = IMPACT[impact_frame].get_size() * scale_factor
		draw_texture_rect(IMPACT[impact_frame], Rect2(Vector2(-impact_size.x * 0.5, -impact_size.y * 0.76), impact_size), false,
			Color.WHITE if aimed else Color(1.0, 0.86, 0.92, 0.65))
		return
	var progress: float = clampf(_age / fall_time, 0.0, 1.0)
	if aimed and allied_impact.is_valid():
		var charge: Color = Color("#ef923f")
		draw_circle(Vector2.ZERO, DAMAGE_RADIUS, Color(charge, 0.19), true, -1.0, true)
		draw_arc(Vector2.ZERO, DAMAGE_RADIUS, 0.0, TAU, 40, Color("#ffce81"), 1.5, true)
		draw_arc(Vector2.ZERO, DAMAGE_RADIUS - 3.0, -PI * 0.5, -PI * 0.5 + TAU * progress,
			40, charge, 2.0, true)
	var frame: int = mini(int(progress * FALL.size()), FALL.size() - 1)
	var size: Vector2 = FALL[frame].get_size() * (0.58 if aimed else 0.44)
	var point: Vector2 = Vector2(-92.0, -178.0) * (1.0 - progress * progress)
	draw_texture_rect(FALL[frame], Rect2(point - Vector2(size.x * 0.5, size.y * 0.75), size), false,
		Color.WHITE if aimed else Color(1.0, 0.87, 0.94, 0.64))
