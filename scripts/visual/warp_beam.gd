extends Node2D
## One contiguous pixel beam: fast travel, a single width pulse, then contraction.
var height: float = 224.0
var _strength: float = 0.0
var _start: float = 0.0
var _end: float = 0.0
var _width: float = 0.0


func set_phase(progress: float, arriving: bool) -> void:
	var phase: float = clampf(progress,0.0,1.0)
	_strength = smoothstep(0.02,0.12,phase)*(1.0-smoothstep(0.64,0.94,phase))
	var expansion: float = smoothstep(0.04,0.30,phase)
	var contraction: float = 1.0-smoothstep(0.42,0.92,phase)
	_width = 2.0+10.0*expansion*contraction
	if arriving:
		_start = 0.0
		# The leading edge reaches the actor quickly, rather than appearing at full length.
		_end = 1.0-pow(1.0-clampf((phase-0.02)/0.26,0.0,1.0),3.0)
	else:
		_start = 1.0-smoothstep(0.0,0.24,phase)
		_end = 1.0-smoothstep(0.58,0.92,phase)
	queue_redraw()


func _draw() -> void:
	if _strength <= 0.0:
		return
	var top: float = floorf(-height+height*_start)
	var bottom: float = floorf(-height+height*_end)
	var length: float = bottom-top
	if length <= 0.0:
		return
	var half_width: float = maxf(1.0,roundf(_width*0.5))
	var opacity: float = ceilf(_strength*8.0)/8.0
	# The one-pixel edge touches the core; nothing is drawn outside this column.
	draw_rect(Rect2(-half_width,top,half_width*2.0,length),Color(0.85,0.76,0.88,opacity*0.60))
	var core_half: float = maxf(0.5,half_width-1.0)
	draw_rect(Rect2(-floorf(core_half),top,maxf(1.0,floorf(core_half)*2.0),length),Color(1.0,0.98,0.98,opacity*0.95))
