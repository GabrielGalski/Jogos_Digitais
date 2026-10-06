extends Node2D
## One short sound wave; direction and origin are captured on emission.
const REACH: float = 112.0
const HALF_ANGLE: float = PI * 32.0 / 180.0
const SEGMENTS: int = 26
const WAVE_COUNT: int = 5

var mode: StringName = &"M03"
var attack: CardAttack
var effects: CombatEffects
var age: float = 0.0
var front: float = 0.0
var fan: Polygon2D
var waves: Array[Line2D] = []
var grain: Array[Line2D] = []
var continuous: bool = false
var source: Marker2D
var cursor_world: Callable


func configure_channel(muzzle: Marker2D, aim: Callable, snapshot: CardAttack, combat_effects: CombatEffects) -> void:
	continuous = true
	source = muzzle
	cursor_world = aim
	configure(Vector2.RIGHT, snapshot, combat_effects)
	front = REACH
	follow_source()


func follow_source() -> void:
	if is_instance_valid(source):
		global_position = source.global_position
		var cursor: Vector2 = cursor_world.call()
		rotation = (cursor - global_position).angle()


func apply_channel_hit(snapshot: CardAttack) -> void:
	attack = snapshot
	_hit_enemies(REACH)


func configure(direction: Vector2, snapshot: CardAttack, combat_effects: CombatEffects) -> void:
	attack = snapshot
	effects = combat_effects
	rotation = direction.angle()
	z_index = 1
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group(&"banshee_bursts")
	fan = Polygon2D.new()
	fan.color = Color(0.57, 0.87, 0.93, 0.055)
	add_child(fan)
	for index: int in range(WAVE_COUNT):
		var line: Line2D = Line2D.new()
		line.width = 1.0 if index % 2 == 0 else 1.5
		line.default_color = Color("#b9f4ee") if index % 2 == 0 else Color("#bca4de")
		line.antialiased = false
		add_child(line)
		waves.append(line)
	for index: int in range(38):
		var fleck: Line2D = Line2D.new()
		fleck.width = 1.0
		fleck.default_color = Color("#d8ffef")
		add_child(fleck)
		grain.append(fleck)
	_update_visual()


func _physics_process(delta: float) -> void:
	if attack == null or continuous:
		return
	age += delta
	front = minf(REACH, age * attack.projectile_speed)
	_hit_enemies(front)
	if age >= attack.projectile_lifetime:
		queue_free()


func _hit_enemies(radius: float) -> void:
	for candidate: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = candidate as Node2D
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if not enemy.has_method(&"is_alive") or not bool(enemy.call(&"is_alive")):
			continue
		var local_target: Vector2 = to_local(enemy.global_position)
		if contains_point(local_target, radius):
			attack.apply_primary_hit(enemy, enemy.global_position, Vector2.RIGHT.rotated(rotation), effects)


func _process(delta: float) -> void:
	if continuous:
		age += delta
		follow_source()
	if attack != null:
		_update_visual()


func contains_point(local_point: Vector2, radius: float = REACH) -> bool:
	return local_point.length() <= radius and absf(local_point.angle()) <= HALF_ANGLE


func _update_visual() -> void:
	var travel_time: float = REACH / attack.projectile_speed
	var fade: float = 1.0 - clampf((age - travel_time) / maxf(0.01, attack.projectile_lifetime - travel_time), 0.0, 1.0)
	var envelope: float = minf(age / 0.025, 1.0) * fade
	if continuous:
		envelope = minf(age / 0.025, 1.0)
	var fan_points: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for index: int in range(SEGMENTS + 1):
		var angle: float = lerpf(-HALF_ANGLE, HALF_ANGLE, float(index) / SEGMENTS)
		fan_points.append(Vector2.from_angle(angle) * front)
	fan.visible = front > 0.5
	if fan.visible:
		fan.polygon = fan_points
	fan.modulate.a = envelope
	var noise_frame: float = floorf(age * 24.0)
	for wave_index: int in range(WAVE_COUNT):
		var radius: float = front - float(wave_index) * 15.0
		if continuous:
			radius = fposmod(age * 145.0 + float(wave_index) * REACH / WAVE_COUNT, REACH)
		var line: Line2D = waves[wave_index]
		line.visible = radius > 5.0
		if not line.visible:
			continue
		var points: PackedVector2Array = PackedVector2Array()
		for sample: int in range(SEGMENTS + 1):
			var t: float = float(sample) / SEGMENTS
			var angle: float = lerpf(-HALF_ANGLE, HALF_ANGLE, t)
			var noise: float = sin(float(sample * 17 + wave_index * 31) + noise_frame * 8.0)
			var rough_radius: float = clampf(radius + noise * 2.2, 0.0, front)
			points.append(Vector2.from_angle(angle) * rough_radius)
		line.points = points
		line.modulate.a = envelope * (0.8 - float(wave_index) * 0.11)
	for index: int in range(grain.size()):
		var fleck: Line2D = grain[index]
		var fraction: float = fposmod(float(index) * 0.618 + noise_frame * 0.071, 1.0)
		var radius: float = lerpf(maxf(3.0, front - 65.0), maxf(3.0, front - 3.0), fraction)
		var angle: float = sin(float(index) * 2.41 + noise_frame * 0.43) * HALF_ANGLE * 0.92
		var center: Vector2 = Vector2.from_angle(angle) * radius
		var offset: Vector2 = Vector2.from_angle(angle) * (1.0 + float(index % 3))
		fleck.points = PackedVector2Array([center, center + offset])
		fleck.modulate.a = envelope * (0.22 + fraction * 0.34)
		fleck.visible = front > 8.0
