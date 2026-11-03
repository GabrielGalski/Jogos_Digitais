extends Node2D
## Small world-space dust flecks at the original character's feet.

var _particles: Array[Dictionary] = []
var _clock: float = 0.0
var _was_rolling: bool = false
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
@onready var player: Player = get_parent() as Player


func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_as_relative = false
	z_index = player.z_index - 1
	_random.randomize()
	player.dash_started.connect(_start)
	player.defeated.connect(_clear)


func _start() -> void:
	_clock = 0.0
	_was_rolling = true
	_emit(6)


func _physics_process(delta: float) -> void:
	if player.intro_locked or player.dead:
		_clear()
		return
	if player.is_dashing():
		_clock -= delta
		if _clock <= 0.0:
			_clock = 0.04
			_emit(2)
	elif _was_rolling:
		_emit(4)
	_was_rolling = player.is_dashing()


func _emit(count: int) -> void:
	for _index: int in range(count):
		var direction: Vector2 = -player.dash_direction.rotated(_random.randf_range(-0.9, 0.9))
		_particles.append({"point": player.surface_world_position() + Vector2(0.0, 7.0), "velocity": direction * _random.randf_range(12.0, 28.0), "age": 0.0})


func _process(delta: float) -> void:
	for index: int in range(_particles.size() - 1, -1, -1):
		var particle: Dictionary = _particles[index]
		particle["age"] = float(particle["age"]) + delta
		particle["point"] = (particle["point"] as Vector2) + (particle["velocity"] as Vector2) * delta
		if float(particle["age"]) >= 0.22:
			_particles.remove_at(index)
	queue_redraw()


func _draw() -> void:
	for particle: Dictionary in _particles:
		var fraction: float = float(particle["age"]) / 0.22
		var tint: Color = Color("#baa1ba")
		tint.a = (1.0 - fraction) * 0.55
		draw_rect(Rect2((particle["point"] as Vector2).round(), Vector2.ONE * (2.0 if fraction < 0.3 else 1.0)), tint)


func _clear() -> void:
	_particles.clear()
	_was_rolling = false
	queue_redraw()
