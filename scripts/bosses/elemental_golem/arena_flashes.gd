extends Node2D
## Staggered white lines charge to their element, cut white once, then disappear in order.
signal finished
signal detonated(hits: int)
signal beam_arrived(index: int)
signal beam_activated(index: int)
signal beam_finished(index: int)

const STYLE: Script = preload("res://scripts/bosses/elemental_golem/elemental_style.gd")
const COLORS: Array[Color] = STYLE.COLORS
# Hand-drawn widths of the two edges. The first and last knots join seamlessly.
static var _edges: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(.72,.91),Vector2(.89,.98),Vector2(.95,.85),Vector2(.39,.94),Vector2(.70,.81),Vector2(.96,.58),Vector2(.72,.91)]),
	PackedVector2Array([Vector2(.92,.65),Vector2(.83,.92),Vector2(.66,.98),Vector2(.81,.46),Vector2(.92,.61),Vector2(.96,.84),Vector2(.92,.65)]),
	PackedVector2Array([Vector2(.65,.88),Vector2(.81,.75),Vector2(.49,.94),Vector2(.89,.97),Vector2(.96,.57),Vector2(.81,.74),Vector2(.65,.88)])
]
@export var beam_count: int = 16
@export var arrival_interval: float = 0.16
@export var entry_duration: float = 0.18
@export var warning_duration: float = 2.65
@export var strike_duration: float = 0.10
@export var fade_duration: float = 0.14
@export var beam_width: float = 18.0
@export var damage_fraction: float = 0.20
var target: Player = null
var element: int = 0
var segments: Array[PackedVector2Array] = []
var safe_point: Vector2 = Vector2.ZERO
var elapsed: float = 0.0
var fired: bool = false
var cancelled: bool = false
var arrived_count: int = 0
var activated_count: int = 0
var finished_count: int = 0
var _entry_view: Rect2 = Rect2()
var _arrived: Array[bool] = []
var _activated: Array[bool] = []
var _completed: Array[bool] = []
var _hit_beams: Array[bool] = []
var _finished: bool = false


func configure(actor: Player, layout: Node2D, element_index: int, sequence: int) -> void:
	target = actor
	element = element_index
	safe_point = layout.call("safe_floor_near", actor.global_position) as Vector2
	_entry_view = _world_view()
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 9137 + sequence * 41 + element_index * 131
	var local_area: Rect2 = layout.get("bounds") as Rect2
	# Cover the initial screen right out to its edges; the cuts stay fixed in the world.
	var area: Rect2 = Rect2(layout.to_global(local_area.position),local_area.size*layout.global_scale).merge(_entry_view).grow(64.0)
	var visible_area: Rect2 = _entry_view.grow(-12.0)
	var initial: Vector2 = actor.global_position + Vector2(0,3)
	var away: Vector2 = initial.direction_to(safe_point)
	if away.is_zero_approx(): away = Vector2.RIGHT
	var columns: int = ceili(sqrt(float(maxi(beam_count,1))))
	for index: int in range(maxi(beam_count,1)):
		for _attempt: int in range(16):
			var forward: Vector2 = away.orthogonal() if index == 0 else Vector2.from_angle(random.randf_range(0.0,TAU))
			var sample: Vector2 = Vector2(float(index%columns)+random.randf_range(0.1,0.9),floorf(float(index)/float(columns))+random.randf_range(0.1,0.9))/float(columns)
			var center: Vector2 = initial if index == 0 else visible_area.position+visible_area.size*sample
			var normal: Vector2 = forward.orthogonal()
			var distance: float = (safe_point-center).dot(normal)
			# A dense pattern still leaves a reachable safe disc on actual floor.
			var clearance: float = beam_width*0.5+24.0
			if absf(distance) < clearance:
				center -= normal * (clearance-absf(distance)) * (1.0 if distance >= 0.0 else -1.0)
			var line: PackedVector2Array = _clip_line(center,forward,area)
			if line.size() != 2 or _clip_line(center,forward,_entry_view).size() != 2: continue
			if index%2 == 1: line.reverse()
			segments.append(line)
			break


func _ready() -> void:
	z_index = 12
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var unlit: CanvasItemMaterial = CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	unlit.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = unlit
	if not _entry_view.has_area(): _entry_view = _world_view()
	for _index: int in range(segments.size()):
		_arrived.append(false)
		_activated.append(false)
		_completed.append(false)
		_hit_beams.append(false)


func arrival_time(index: int) -> float:
	return float(index)*maxf(arrival_interval,0.0)


func activation_time(index: int) -> float:
	return arrival_time(index)+maxf(entry_duration,0.01)+maxf(warning_duration,0.0)


func completion_time(index: int) -> float:
	return activation_time(index)+maxf(strike_duration,0.01)+maxf(fade_duration,0.01)


func total_duration() -> float:
	return completion_time(maxi(segments.size()-1,0))


func charge_progress(index: int) -> float:
	return clampf((elapsed-arrival_time(index)-maxf(entry_duration,0.01))/maxf(warning_duration,0.01),0.0,1.0)


func charge_color(index: int) -> Color:
	return Color.WHITE.lerp(COLORS[element],smoothstep(0.0,1.0,charge_progress(index)))


func _physics_process(delta: float) -> void:
	if cancelled or _finished: return
	if not is_instance_valid(target) or target.dead or target.intro_locked:
		cancel()
		return
	elapsed += delta
	for index: int in range(segments.size()):
		if not _arrived[index] and elapsed >= arrival_time(index)+maxf(entry_duration,0.01):
			_arrived[index] = true
			arrived_count += 1
			beam_arrived.emit(index)
		if not _activated[index] and elapsed >= activation_time(index):
			_activated[index] = true
			activated_count += 1
			fired = true
			# The white cut is one impact. Coloured warnings and fading cuts are harmless.
			if not target.is_dashing() and not target.is_fall_recovery_invulnerable() and _beam_contains(index,target.global_position+Vector2(0,3)):
				_hit_beams[index] = true
				target.receive_skybreaker_hit(target.max_health*damage_fraction, get_parent() as Node2D)
				detonated.emit(1)
			beam_activated.emit(index)
			if target.dead or cancelled: return
		if not _completed[index] and elapsed >= completion_time(index):
			_completed[index] = true
			finished_count += 1
			beam_finished.emit(index)
	if elapsed >= total_duration():
		_finished = true
		finished.emit()
		queue_free()
	queue_redraw()


func hit_count(point: Vector2) -> int:
	var result: int = 0
	for index: int in range(segments.size()):
		if _beam_contains(index,point): result += 1
	return result


func _beam_contains(index: int, point: Vector2) -> bool:
	var segment: PackedVector2Array = segments[index]
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point,segment[0],segment[1])) <= beam_width*0.5


func cancel() -> void:
	if cancelled: return
	cancelled = true
	set_physics_process(false)
	queue_free()


func _world_view() -> Rect2:
	if not is_instance_valid(target): return Rect2(-240,-135,480,270)
	var inverse: Transform2D = target.get_canvas_transform().affine_inverse()
	var view: Rect2 = target.get_viewport_rect()
	var result: Rect2 = Rect2(inverse*view.position,Vector2.ZERO)
	for corner: Vector2 in [view.end,Vector2(view.end.x,view.position.y),Vector2(view.position.x,view.end.y)]:
		result = result.expand(inverse*corner)
	return result


func _clip_line(center: Vector2, forward: Vector2, area: Rect2) -> PackedVector2Array:
	if forward.is_zero_approx(): return PackedVector2Array()
	var lower: float = -INF
	var upper: float = INF
	for axis: int in range(2):
		if absf(forward[axis]) < 0.0001:
			if center[axis] < area.position[axis] or center[axis] > area.end[axis]: return PackedVector2Array()
			continue
		var first: float = (area.position[axis]-center[axis])/forward[axis]
		var last: float = (area.end[axis]-center[axis])/forward[axis]
		lower = maxf(lower,minf(first,last))
		upper = minf(upper,maxf(first,last))
		if upper < lower: return PackedVector2Array()
	return PackedVector2Array([center+forward*lower,center+forward*upper])


func _draw() -> void:
	for index: int in range(segments.size()):
		var age: float = elapsed-arrival_time(index)
		if age < 0.0: continue
		var segment: PackedVector2Array = segments[index]
		var start: Vector2 = to_local(segment[0])
		var end: Vector2 = to_local(segment[1])
		var cut_age: float = elapsed-activation_time(index)
		if cut_age < 0.0:
			var reveal: float = smoothstep(0.0,1.0,age/maxf(entry_duration,0.01))
			var head: Vector2 = start.lerp(end,reveal)
			var tint: Color = charge_color(index)
			var width: float = lerpf(1.1,2.1,charge_progress(index))
			draw_line(start,head,Color(tint,0.10),width+2.0,true)
			draw_line(start,head,Color(tint,0.94),width,true)
		elif elapsed < completion_time(index):
			var fade: float = smoothstep(0.0,maxf(fade_duration,0.01),maxf(cut_age-strike_duration,0.0))
			var alpha: float = 1.0-fade
			var width: float = lerpf(beam_width,0.5,fade)
			_draw_slash(start,end,width*0.5,alpha,(index+element)%_edges.size())


func _draw_slash(start: Vector2, end: Vector2, radius: float, alpha: float, pattern: int) -> void:
	var length: float = start.distance_to(end)
	if length < 0.01: return
	var axis: Vector2 = start.direction_to(end)
	var side: Vector2 = axis.orthogonal()*radius
	var knots: PackedVector2Array = _edges[pattern]
	var step: float = 35.0+float(pattern)*4.0
	var upper: PackedVector2Array = PackedVector2Array()
	var lower: PackedVector2Array = PackedVector2Array()
	for i: int in range(ceili(length/step)+1):
		var distance: float = minf(i*step,length)
		var k: int = maxi(i-1,0)%(knots.size()-1)
		var edge: Vector2 = knots[0] if i==0 else knots[k].lerp(knots[k+1],clampf(distance/step-float(i-1),0.0,1.0))
		var at: Vector2 = start+axis*distance
		upper.append(at+side*edge.x)
		lower.append(at-side*edge.y)
	var ink: Color = Color(1,1,1,alpha)
	draw_polyline(upper,Color(COLORS[element],alpha*.18),2.0,true)
	draw_polyline(lower,Color(COLORS[element],alpha*.18),2.0,true)
	lower.reverse()
	upper.append_array(lower)
	draw_colored_polygon(upper,ink)
	# Long split tips: one edge peels away from the blade and tapers back to a point.
	for i: int in range(pattern,ceili(length/step)-2,3):
		var at: Vector2 = start+axis*(float(i)*step)
		var reach: float = minf(length-float(i)*step,step*2.8)
		var lip: Vector2 = side if (i+pattern)%2==0 else -side
		draw_colored_polygon(PackedVector2Array([at+lip*.56,at+axis*reach*.42+lip*1.08,
			at+axis*reach+lip*1.32,at+axis*reach*.46+lip*.86]),ink)
