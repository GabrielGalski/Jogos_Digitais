extends Node2D
## Head-level speed stroke. Presentation only: samples actual travel, not input.

@export var tint: Color = Color("#4c2f49")
@export var head_pixel_offset: Vector2 = Vector2(0.0, -21.0)
@export var fast_speed_multiplier: float = 1.55
@export var maximum_length: float = 20.0
@export var width: float = 1.0

var strength: float = 0.0
var target_strength: float = 0.0
var motion_direction: Vector2 = Vector2.RIGHT
var target_direction: Vector2 = Vector2.RIGHT
var pulse_phase: float = PI * 0.25
var pulse_alpha: float = 0.0
var head_anchor: Vector2 = Vector2.ZERO
var line_start: Vector2 = Vector2.ZERO
var line_end: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.ZERO
var _travel_since_draw: float = 0.0

@onready var player: Player = get_parent() as Player
@onready var visual: NoxVisual = get_node("../Body") as NoxVisual


func _ready() -> void:
	if player == null or visual == null:
		set_physics_process(false)
		set_process(false)
		hide()
		return
	_last_position = player.global_position
	hide()


func _physics_process(delta: float) -> void:
	var displacement: Vector2 = player.global_position - _last_position
	_last_position = player.global_position
	var distance: float = displacement.length()
	var speed: float = distance / maxf(delta, 0.0001)
	# Locks, respawns and teleports must never look like fast locomotion.
	if player.intro_locked or player.dead or speed > maxf(player.dash_speed, player.movement_speed) * 2.0:
		reset_effect()
		return
	var threshold: float = player.movement_speed * fast_speed_multiplier
	target_strength = clampf((speed - threshold) / maxf(player.dash_speed - threshold, 1.0), 0.0, 1.0)
	if target_strength > 0.0:
		if strength < 0.02:
			pulse_phase = PI * 0.25
			motion_direction = displacement.normalized()
		target_direction = displacement.normalized()
		_travel_since_draw += distance


func _process(delta: float) -> void:
	var response: float = 36.0 if target_strength > strength else 24.0
	strength = lerpf(strength, target_strength, 1.0 - exp(-response * delta))
	motion_direction = motion_direction.lerp(target_direction, 1.0 - exp(-32.0 * delta)).normalized()
	pulse_phase = fposmod(pulse_phase + _travel_since_draw * 0.16, TAU)
	_travel_since_draw = 0.0
	pulse_alpha = smoothstep(0.0, 0.85, maxf(sin(pulse_phase), 0.0)) * strength
	# Account for the new canvas offset plus the dash's scale/lean.
	head_anchor = to_local(visual.to_global(visual.offset + head_pixel_offset)).round()
	line_start = (head_anchor + motion_direction * 2.0).round()
	line_end = (head_anchor - motion_direction * lerpf(5.0, maximum_length, strength)).round()
	visible = strength > 0.02 and pulse_alpha > 0.03
	queue_redraw()


func _draw() -> void:
	var stroke: Color = tint
	stroke.a *= pulse_alpha
	draw_line(line_end, line_start, stroke, width, false)


func reset_effect() -> void:
	strength = 0.0
	target_strength = 0.0
	pulse_alpha = 0.0
	_travel_since_draw = 0.0
	pulse_phase = PI * 0.25
	hide()
	queue_redraw()
