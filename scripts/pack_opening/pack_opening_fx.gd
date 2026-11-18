class_name PackOpeningFX
extends Node2D
## Bounded CPU shapes keep the burst readable on Compatibility.

class Mote:
	extends RefCounted
	var at: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var rotation: float = 0.0
	var spin: float = 0.0
	var width: float = 2.0
	var lifetime: float = 0.5
	var age: float = 0.0
	var tint: Color = Color.WHITE
	var diamond: bool = false

@export var foreground: bool = false
var profile: PackOpeningProfile
var motes: Array[Mote] = []
var burst_count: int = 0
var pulse_age: float = 10.0
var burst_origin: Vector2 = Vector2.ZERO
var guide_from: Vector2 = Vector2.ZERO
var guide_to: Vector2 = Vector2.ZERO
var guide_visible: bool = false
var cutting: bool = false
var stroke_points: PackedVector2Array = PackedVector2Array()
var trail_age: float = 10.0
var clock: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func reset_fx() -> void:
	motes.clear()
	pulse_age = 10.0
	trail_age = 10.0
	guide_visible = false
	cutting = false
	stroke_points.clear()
	queue_redraw()


func show_guide(from: Vector2, to: Vector2) -> void:
	guide_from = from
	guide_to = to
	guide_visible = true
	queue_redraw()


func begin_stroke(at: Vector2) -> void:
	stroke_points = PackedVector2Array([at])
	cutting = true
	trail_age = 0.0
	queue_redraw()


func trace_to(at: Vector2) -> void:
	trail_age = 0.0
	if stroke_points.is_empty() or stroke_points[-1].distance_to(at) >= 1.0:
		stroke_points.append(at)
	while stroke_points.size() > 16:
		stroke_points.remove_at(0)
	if stroke_points.size() == 2 and stroke_points[0].distance_to(at) > 200.0:
		stroke_points[0] = at + (stroke_points[0] - at).normalized() * 200.0
	queue_redraw()


func finish_cut() -> void:
	guide_visible = false
	cutting = false
	trail_age = 0.0


func burst(at: Vector2, cut_direction: float) -> void:
	if profile == null:
		return
	burst_count += 1
	burst_origin = at
	pulse_age = 0.0
	var amount: int = profile.front_particles if foreground else profile.back_particles
	for index: int in range(amount):
		var mote: Mote = Mote.new()
		var angle: float = TAU * float(index) / float(maxi(amount, 1)) + rng.randf_range(-0.15, 0.15)
		var radial: Vector2 = Vector2(cos(angle), sin(angle) * 0.75)
		var speed: float = rng.randf_range(profile.burst_speed_min, profile.burst_speed_max) * (0.55 if foreground else 1.0)
		# Start behind the rim so the expansion clears the opaque card quickly.
		var radius: float = 6.0 if foreground else profile.burst_radius * rng.randf_range(0.7, 1.0)
		mote.at = at + radial * radius
		mote.velocity = radial * speed + Vector2(cut_direction * 12.0, -40.0)
		mote.lifetime = profile.particle_lifetime * rng.randf_range(0.65, 1.1)
		mote.width = rng.randf_range(2.0, 3.5) if foreground else rng.randf_range(3.0, 5.5)
		mote.rotation = rng.randf_range(-PI, PI)
		mote.spin = rng.randf_range(-5.0, 5.0)
		mote.tint = profile.burst_colors[index % profile.burst_colors.size()]
		mote.diamond = index % 5 == 0
		motes.append(mote)
	queue_redraw()


func _process(delta: float) -> void:
	var had_particles: bool = not motes.is_empty()
	clock += delta
	pulse_age += delta
	trail_age += delta
	for index: int in range(motes.size() - 1, -1, -1):
		var mote: Mote = motes[index]
		mote.age += delta
		if mote.age >= mote.lifetime:
			motes.remove_at(index)
			continue
		mote.velocity *= exp(-2.0 * delta)
		mote.velocity.y += 75.0 * delta
		mote.at += mote.velocity * delta
		mote.rotation += mote.spin * delta
	if had_particles or guide_visible or cutting or pulse_age < 0.4 or trail_age < 0.22:
		queue_redraw()
	elif pulse_age < 0.5 or trail_age < 0.28:
		queue_redraw()


func _draw() -> void:
	if profile == null:
		return
	if not foreground and pulse_age < 0.34:
		var pulse: float = 1.0 - pulse_age / 0.34
		for ring: int in range(5, 0, -1):
			draw_circle(burst_origin, float(ring) * 15.0 + pulse_age * 38.0, Color(0.84, 0.39, 0.91, pulse * 0.035))
		var radius: float = 28.0 + (1.0 - pow(pulse, 2.0)) * 62.0
		draw_arc(burst_origin, radius, 0.0, TAU, 48, Color(profile.cut_color, pulse * 0.55), 2.0)
	for mote: Mote in motes:
		var opacity: float = 1.0 - smoothstep(mote.lifetime * 0.35, mote.lifetime, mote.age)
		var tint: Color = mote.tint
		tint.a *= opacity * (0.90 if foreground else 1.0)
		var extent: float = maxf(1.0, roundf(mote.width * (1.0 - 0.3 * mote.age / mote.lifetime)))
		var point: Vector2 = mote.at.round()
		if mote.diamond:
			draw_circle(point, extent * 1.7, Color(tint, tint.a * 0.12))
		if mote.diamond:
			var vertices: PackedVector2Array = PackedVector2Array()
			for corner: int in range(4):
				vertices.append(point + Vector2(extent, 0.0).rotated(mote.rotation + float(corner) * PI * 0.5))
			draw_colored_polygon(vertices, tint)
		else:
			draw_rect(Rect2(point, Vector2(extent, extent)), tint)
	if not foreground:
		return
	if guide_visible:
		var guide: Color = profile.guide_color
		guide.a = 0.65 + sin(clock * 3.0) * 0.12
		var along: Vector2 = (guide_to - guide_from).normalized()
		var normal: Vector2 = Vector2(-along.y, along.x)
		# The new wrappers have no baked-in dots. Draw them on the projected seal.
		var length: float = guide_from.distance_to(guide_to)
		for step: int in range(0, floori(length), 6):
			var start: Vector2 = guide_from + along * float(step)
			var end: Vector2 = guide_from + along * minf(float(step) + 3.0, length)
			draw_line(start, end, Color("#261427"), 3.0)
			draw_line(start, end, Color(profile.cut_color, 0.95), 1.0)
		for point: Vector2 in [guide_from - along * 7.0, guide_to + along * 7.0]:
			draw_line(point - normal * 3.0, point + normal * 3.0, guide, 1.0)
	if (cutting or trail_age < 0.22) and stroke_points.size() > 1:
		var opacity: float = 1.0 if cutting else 1.0 - trail_age / 0.22
		for index: int in range(1, stroke_points.size()):
			var from: Vector2 = stroke_points[index - 1].round()
			var to: Vector2 = stroke_points[index].round()
			var weight: float = float(index) / float(stroke_points.size() - 1)
			draw_line(from, to, Color(0.91, 0.38, 0.87, opacity * 0.20), 9.0 * weight)
			draw_line(from, to, Color(profile.guide_color, opacity * 0.75), 4.0 * weight)
			draw_line(from, to, Color(profile.cut_color, opacity), maxf(1.0, 2.0 * weight))
