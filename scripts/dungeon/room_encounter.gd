extends Node2D
## Owns one bounded encounter; geometry and scene transitions live elsewhere.
signal progress_changed
signal cleared

const MINOTAUR: PackedScene = preload("res://scenes/enemies/minotaur.tscn")
enum Phase { WAITING, SPAWNING, COMBAT, WAVE_BREAK, ELITE_TRIGGER, CLEARED, CANCELLED }
@export var bounds: Rect2 = Rect2(0, 0, 320, 192)
@export var spawn_points: PackedVector2Array = PackedVector2Array()
@export var waves: Array[int] = [6]
@export var spawn_interval: float = 0.8
@export var elite_placeholder: bool = false
var phase: Phase = Phase.WAITING
var player: Player
var wave_index: int = 0
var spawned: int = 0
var defeated_count: int = 0
var alive: int = 0
var wave_spawned: int = 0
var timer: float = 0.0
var pending_position: Vector2 = Vector2.ZERO

func begin(target: Player) -> void:
	if phase != Phase.WAITING:
		return
	player = target
	phase = Phase.SPAWNING
	_prepare_spawn()
	progress_changed.emit()

func total() -> int:
	var count: int = 0
	for amount: int in waves:
		count += amount
	return count

func cancel() -> void:
	phase = Phase.CANCELLED
	queue_redraw()

func _physics_process(delta: float) -> void:
	if phase in [Phase.WAITING, Phase.CLEARED, Phase.CANCELLED]:
		return
	if not is_instance_valid(player) or player.dead:
		cancel()
		return
	timer -= delta
	match phase:
		Phase.SPAWNING:
			queue_redraw()
			if timer <= 0.0:
				_spawn()
		Phase.WAVE_BREAK:
			if timer <= 0.0:
				phase = Phase.SPAWNING
				_prepare_spawn()
				progress_changed.emit()
		Phase.ELITE_TRIGGER:
			if timer <= 0.0:
				_finish()

func _prepare_spawn() -> void:
	# Prefer the authored point in sequence; if Nox occupies it choose the farthest.
	pending_position = spawn_points[spawned % spawn_points.size()]
	if pending_position.distance_to(player.global_position) < 64.0:
		for point: Vector2 in spawn_points:
			if point.distance_squared_to(player.global_position) > pending_position.distance_squared_to(player.global_position):
				pending_position = point
	timer = spawn_interval
	queue_redraw()

func _spawn() -> void:
	var enemy: Minotaur = MINOTAUR.instantiate() as Minotaur
	enemy.position = pending_position
	add_child(enemy)
	enemy.setup(player, self, bounds)
	enemy.died.connect(_on_enemy_died)
	enemy.reset_physics_interpolation()
	spawned += 1
	wave_spawned += 1
	alive += 1
	if wave_spawned < waves[wave_index]:
		_prepare_spawn()
	else:
		phase = Phase.COMBAT
	queue_redraw()
	progress_changed.emit()

func _on_enemy_died(_enemy: Minotaur) -> void:
	if phase == Phase.CANCELLED:
		return
	alive -= 1
	defeated_count += 1
	if alive == 0 and phase == Phase.COMBAT:
		if wave_index + 1 < waves.size():
			wave_index += 1
			wave_spawned = 0
			phase = Phase.WAVE_BREAK
			timer = 1.0
		elif elite_placeholder:
			phase = Phase.ELITE_TRIGGER
			timer = 1.2
		else:
			_finish()
	progress_changed.emit()

func _finish() -> void:
	phase = Phase.CLEARED
	queue_redraw()
	cleared.emit()
	progress_changed.emit()

func _draw() -> void:
	if phase == Phase.SPAWNING:
		var radius: float = lerpf(16.0, 11.0, clampf(1.0 - timer / spawn_interval, 0.0, 1.0))
		draw_arc(to_local(pending_position), radius, 0.0, TAU, 24, Color("#df86aa"), 1.0)
