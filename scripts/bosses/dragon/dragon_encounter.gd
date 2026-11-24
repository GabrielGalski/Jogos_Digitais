extends CharacterBody2D
## The dragon moves inside the clearing. The encounter rectangle only controls when combat ends.

signal combat_changed

const ORB = preload("res://scripts/bosses/dragon/dragon_orb.gd")
const METEOR = preload("res://scripts/bosses/dragon/dragon_meteor.gd")
const HUD: PackedScene = preload("res://scenes/ui/asterion_boss_bar.tscn")
const REWARD_PEDESTAL: Script = preload("res://scripts/bosses/dragon/dragon_reward_pedestal.gd")
const FRAMES: Array[Texture2D] = [
	preload("res://assets/enemies/dragon/dragon1.png"),
	preload("res://assets/enemies/dragon/dragon2.png"),
	preload("res://assets/enemies/dragon/dragon3.png"),
	preload("res://assets/enemies/dragon/dragon4.png"),
	preload("res://assets/enemies/dragon/dragon5.png"),
	preload("res://assets/enemies/dragon/dragon6.png"),
]

enum State { WAITING, HUNT, RETREAT, BARRAGE, ASCENT, AIR, LANDING, DEFEATED }

const MAX_HEALTH: float = 480.0
const NOTICE_TIME: float = 0.65
const ORB_DAMAGE: int = 18
const ASCENT_TIME: float = 0.42
const AIR_HEIGHT: float = 155.0
const LAND_TIME: float = 0.53
const ARENA_MARGIN: float = 28.0
const HUNT_WAVES: int = 4
const HUNT_INTERVAL: float = 0.62
const HUNT_SPEED: float = 83.0
const HUNT_DISTANCE: float = 68.0
const AIM_SPREAD: float = 0.15
const RETREAT_DISTANCE: float = 130.0
const RETREAT_SPEED: float = 128.0
const RETREAT_LIMIT: float = 1.10
const SPIRAL_ARMS: int = 7
const SPIRAL_GROUP: int = 13
const SPIRAL_GROUPS: int = 2
const WAVES: Array[int] = [8, 12]
const PARTICLES_PER_WAVE: Array[int] = [4, 6]
const FALL_TIMES: Array[float] = [0.90, 0.61]
const WAVE_INTERVALS: Array[float] = [1.08, 0.81]

var player: Player
var arena_bounds: Rect2
var encounter_bounds: Rect2
var ground_query: Callable
var terrain_height_query: Callable
var state: State = State.WAITING
var health: float = MAX_HEALTH
var phase_count: int = 0

var _progress: Node
var _home: Vector2
var _retreat_goal: Vector2
var _sprite: Sprite2D
var _body_shape: CollisionShape2D
var _shots: Node2D
var _bar: Control
var _health_bar: Range
var _notice: float = 0.0
var _state_age: float = 0.0
var _ambient_age: float = 0.0
var _hit_flash: float = 0.0
var _altitude: float = 0.0
var _ground_height: float = 0.0
var _attack_in: float = 0.0
var _attack_index: int = 0
var _spin: float = 0.0
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


static func build(layers: Array, subject: Player, is_ground: Callable, terrain_height: Callable, world: Node2D) -> void:
	var arena: Rect2 = Rect2()
	var encounter: Rect2 = Rect2()
	var spawn: Vector2 = Vector2.INF
	var reward_anchor: Vector2 = Vector2.INF
	for layer: Dictionary in layers:
		if String(layer.get("__identifier", "")) != "GameplayAreas":
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			var identifier: String = String(entity.get("__identifier", ""))
			if identifier not in ["DragonArena", "DragonEncounter", "DragonSpawn", "DragonRewardPedestal"]:
				continue
			var pixel: Array = entity["px"]
			var point: Vector2 = Vector2(float(pixel[0]), float(pixel[1])) + offset
			if identifier == "DragonSpawn":
				spawn = point
				continue
			if identifier == "DragonRewardPedestal":
				reward_anchor = point
				continue
			var pivot: Array = entity["__pivot"]
			var dimensions: Vector2 = Vector2(float(entity["width"]), float(entity["height"]))
			var bounds: Rect2 = Rect2(point - dimensions * Vector2(float(pivot[0]), float(pivot[1])), dimensions)
			if identifier == "DragonArena":
				arena = bounds
			else:
				encounter = bounds
	if not arena.has_point(spawn) or not encounter.encloses(arena):
		push_error("Room_2: valide DragonSpawn, DragonArena e DragonEncounter no LDtk.")
		return
	var dragon: CharacterBody2D = load("res://scripts/bosses/dragon/dragon_encounter.gd").new() as CharacterBody2D
	dragon.name = "DragonEncounter"
	dragon.position = spawn
	dragon.set("arena_bounds", Rect2(world.to_global(arena.position), arena.size))
	dragon.set("encounter_bounds", Rect2(world.to_global(encounter.position), encounter.size))
	dragon.set("player", subject)
	dragon.set("ground_query", is_ground)
	dragon.set("terrain_height_query", terrain_height)
	world.add_child(dragon)
	if reward_anchor == Vector2.INF:
		reward_anchor = arena.get_center()
	var reward_world_point: Vector2 = world.to_global(reward_anchor)
	if not bool(is_ground.call(reward_world_point)):
		push_warning("Room_2: DragonRewardPedestal precisa ficar no piso jogável.")
		return
	var pedestal: Node2D = REWARD_PEDESTAL.new() as Node2D
	pedestal.name = "DragonRewardPedestal"
	world.add_child(pedestal)
	pedestal.call("configure", subject, dragon, reward_anchor, float(terrain_height.call(reward_world_point)))


func _ready() -> void:
	set_meta(&"is_boss", true)
	z_index = 3
	collision_layer = 0
	collision_mask = 1
	_home = global_position
	_progress = get_node("/root/DragonProgress")
	_random.randomize()

	_body_shape = CollisionShape2D.new()
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = 20.0
	capsule.height = 53.0
	_body_shape.shape = capsule
	_body_shape.position.y = -25.0
	_body_shape.disabled = true
	add_child(_body_shape)

	_sprite = Sprite2D.new()
	_sprite.name = "DragonSprite"
	_sprite.texture = FRAMES[0]
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_update_pose()

	_shots = Node2D.new()
	_shots.name = "Attacks"
	_shots.top_level = true
	add_child(_shots)
	_shots.global_position = Vector2.ZERO

	var hud_layer: CanvasLayer = CanvasLayer.new()
	hud_layer.layer = 54
	add_child(hud_layer)
	_bar = HUD.instantiate() as Control
	(_bar.get_node("Name") as Label).text = "Dragão"
	_health_bar = _bar.get_node("HP") as Range
	_health_bar.max_value = MAX_HEALTH
	_health_bar.value = health
	hud_layer.add_child(_bar)
	_bar.hide()

	if not bool(_progress.call("can_spawn")):
		state = State.DEFEATED
		_sprite.hide()


func _physics_process(delta: float) -> void:
	_ambient_age += delta
	if state == State.DEFEATED:
		if bool(_progress.call("can_spawn")):
			_reset_encounter()
		return
	var present: bool = _subject_in_encounter()
	if state == State.WAITING:
		_notice = _notice + delta if present and _dragon_on_screen() else 0.0
		if _notice >= NOTICE_TIME:
			_begin_combat()
	elif not present:
		_reset_encounter()
	else:
		_state_age += delta
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		match state:
			State.HUNT: _update_hunt(delta)
			State.RETREAT: _update_retreat(delta)
			State.BARRAGE: _update_barrage(delta)
			State.ASCENT: _update_ascent()
			State.AIR: _update_meteors(delta)
			State.LANDING: _update_landing()
	_update_pose()
	queue_redraw()


func _subject_in_encounter() -> bool:
	return is_instance_valid(player) and not player.dead and not player.intro_locked and encounter_bounds.has_point(player.global_position)


func _dragon_on_screen() -> bool:
	var painted_rect: Rect2 = _sprite.get_global_transform_with_canvas() * _sprite.get_rect()
	var screen: Rect2 = get_viewport().get_visible_rect().grow(-8.0)
	var visible_part: Vector2 = painted_rect.intersection(screen).size
	return visible_part.x >= 16.0 and visible_part.y >= 20.0


func _begin_combat() -> void:
	_bar.show()
	_enter_hunt(0.52)
	combat_changed.emit()


func _enter_hunt(delay: float) -> void:
	state = State.HUNT
	_state_age = 0.0
	_attack_index = 0
	_attack_in = delay
	_altitude = 0.0
	_enable_body(true)


func _enable_body(active: bool) -> void:
	collision_layer = 4 if active else 0
	_body_shape.set_deferred("disabled", not active)
	if active:
		if not is_in_group(&"enemy_bodies"):
			add_to_group(&"enemy_bodies")
	elif is_in_group(&"enemy_bodies"):
		remove_from_group(&"enemy_bodies")


func _orb_origin() -> Vector2:
	return to_global(Vector2(0, -22))


func _spawn_orb(direction: Vector2, speed: float) -> void:
	var shot: ORB = ORB.new()
	shot.target = player
	shot.shooter = self
	shot.direction = direction
	shot.position = _shots.to_local(_orb_origin())
	shot.speed = speed
	shot.damage = ORB_DAMAGE
	shot.radius = 3.2
	shot.encounter_bounds = encounter_bounds
	shot.height_query = terrain_height_query
	shot._visual_height = _ground_height
	_shots.add_child(shot)


func _move_in_arena(goal: Vector2, speed: float, delta: float) -> void:
	var interior: Rect2 = arena_bounds.grow(-ARENA_MARGIN)
	var destination: Vector2 = global_position.move_toward(goal.clamp(interior.position, interior.end), speed * delta)
	if destination != global_position and bool(ground_query.call(destination)):
		move_and_collide(destination - global_position)


func _update_hunt(delta: float) -> void:
	var gap: Vector2 = player.global_position - global_position
	if gap.length_squared() > HUNT_DISTANCE * HUNT_DISTANCE:
		_move_in_arena(player.global_position - gap.normalized() * HUNT_DISTANCE, HUNT_SPEED, delta)

	_attack_in -= delta
	if _attack_in > 0.0:
		return
	var aim: float = _orb_origin().angle_to_point(player.global_position + Vector2(0, 3))
	for lane: int in range(-1, 2):
		_spawn_orb(Vector2.from_angle(aim + float(lane) * AIM_SPREAD), 146.0)
	_attack_index += 1
	if _attack_index >= HUNT_WAVES:
		_begin_retreat()
	else:
		_attack_in += HUNT_INTERVAL


func _begin_retreat() -> void:
	state = State.RETREAT
	_state_age = 0.0
	var interior: Rect2 = arena_bounds.grow(-ARENA_MARGIN)
	var player_point: Vector2 = player.global_position
	var away: Vector2 = player_point.direction_to(global_position)
	if away.is_zero_approx():
		away = Vector2.LEFT

	# Try lateral routes when a straight retreat would run into the edge of the clearing.
	_retreat_goal = global_position
	var best_distance: float = -1.0
	for angle: float in [0.0, -0.72, 0.72, -1.44, 1.44, -2.1, 2.1]:
		var point: Vector2 = (global_position + away.rotated(angle) * RETREAT_DISTANCE).clamp(interior.position, interior.end)
		if point.distance_squared_to(global_position) < 28.0 * 28.0 or not bool(ground_query.call(point)):
			continue
		var gap: float = point.distance_squared_to(player_point)
		if gap > best_distance:
			best_distance = gap
			_retreat_goal = point


func _update_retreat(delta: float) -> void:
	_move_in_arena(_retreat_goal, RETREAT_SPEED, delta)
	if global_position.distance_squared_to(_retreat_goal) <= 4.0 or _state_age >= RETREAT_LIMIT:
		state = State.BARRAGE
		_state_age = 0.0
		_attack_index = 0
		_attack_in = 0.38


func _update_barrage(delta: float) -> void:
	_attack_in -= delta
	if _attack_in > 0.0:
		return
	if _attack_index >= SPIRAL_GROUP * SPIRAL_GROUPS:
		_enter_hunt(0.54)
		return
	for arm: int in range(SPIRAL_ARMS):
		_spawn_orb(Vector2.from_angle(_spin + TAU * float(arm) / float(SPIRAL_ARMS)), 118.0)
	_spin = fposmod(_spin + 0.17, TAU)
	_attack_index += 1
	_attack_in += 0.16 if _attack_index % SPIRAL_GROUP != 0 else 0.98


func _begin_air_phase() -> void:
	phase_count += 1
	state = State.ASCENT
	_state_age = 0.0
	_attack_index = 0
	_enable_body(false)
	_clear_attacks()


func _update_ascent() -> void:
	var ratio: float = minf(_state_age / ASCENT_TIME, 1.0)
	_altitude = AIR_HEIGHT * (1.0 - pow(1.0 - ratio, 2.0))
	if ratio >= 1.0:
		state = State.AIR
		_state_age = 0.0
		_attack_in = 0.30


func _update_meteors(delta: float) -> void:
	var phase: int = phase_count - 1
	_attack_in -= delta
	_altitude = AIR_HEIGHT + 4.0 * sin(_state_age * 4.0)
	if _attack_in > 0.0:
		return
	if _attack_index >= WAVES[phase]:
		state = State.LANDING
		_state_age = 0.0
		return
	var aim: Vector2 = player.global_position
	_spawn_meteor(aim, FALL_TIMES[phase], true)
	for _index: int in range(PARTICLES_PER_WAVE[phase]):
		var point: Vector2 = _random_impact(aim)
		if point != Vector2.INF:
			_spawn_meteor(point, FALL_TIMES[phase] * _random.randf_range(0.78, 1.12), false)
	_attack_index += 1
	_attack_in += WAVE_INTERVALS[phase] if _attack_index < WAVES[phase] else FALL_TIMES[phase] * 1.12 + 0.35


func _random_impact(aim: Vector2) -> Vector2:
	var drop_bounds: Rect2 = arena_bounds.grow(-20.0)
	for _attempt: int in range(12):
		var point: Vector2 = Vector2(_random.randf_range(drop_bounds.position.x, drop_bounds.end.x),
			_random.randf_range(drop_bounds.position.y, drop_bounds.end.y))
		if point.distance_squared_to(aim) >= 82.0 * 82.0 and bool(ground_query.call(point)):
			return point
	return Vector2.INF


func _spawn_meteor(point: Vector2, flight_time: float, aimed: bool) -> void:
	var meteor: METEOR = METEOR.new()
	meteor.position = _shots.to_local(point)
	meteor.target = player
	meteor.source = self
	meteor.aimed = aimed
	meteor.fall_time = flight_time
	meteor.ground_height = _height_at(point)
	_shots.add_child(meteor)


func _update_landing() -> void:
	var ratio: float = minf(_state_age / LAND_TIME, 1.0)
	_altitude = AIR_HEIGHT * (1.0 - ratio * ratio)
	if ratio >= 1.0:
		_enter_hunt(0.72)


func _update_pose() -> void:
	var airborne: bool = state in [State.ASCENT, State.AIR, State.LANDING]
	var frame: int = 2 if airborne else int(_ambient_age * 8.0) % FRAMES.size()
	_sprite.texture = FRAMES[frame]
	_ground_height = _height_at(global_position)
	_sprite.position.y = -35.0 - _altitude - _ground_height
	if state in [State.HUNT, State.RETREAT, State.BARRAGE]:
		var facing: float = player.global_position.x - global_position.x
		if absf(facing) > 3.0:
			_sprite.flip_h = facing < 0.0
	_sprite.modulate = Color(1.8, 1.4, 1.5) if _hit_flash > 0.0 else Color.WHITE


func _height_at(point: Vector2) -> float:
	return float(terrain_height_query.call(point)) if terrain_height_query.is_valid() else 0.0


func _clear_attacks() -> void:
	for attack: Node in _shots.get_children():
		attack.call("dismiss")


func _reset_encounter() -> void:
	_clear_attacks()
	_enable_body(false)
	global_position = _home
	reset_physics_interpolation()
	state = State.WAITING
	health = MAX_HEALTH
	phase_count = 0
	_notice = 0.0
	_spin = 0.0
	_hit_flash = 0.0
	_altitude = 0.0
	_health_bar.value = health
	_bar.hide()
	_sprite.show()
	combat_changed.emit()


func take_damage(amount: float) -> void:
	if state not in [State.HUNT, State.RETREAT, State.BARRAGE] or not _subject_in_encounter() or amount <= 0.0:
		return
	var threshold: float = MAX_HEALTH * (0.5 - 0.25 * float(phase_count)) if phase_count < 2 else 0.0
	# The two flyovers happen even when a single hit would cross both thresholds.
	health = maxf(threshold, health - amount)
	_health_bar.value = health
	_hit_flash = 0.10
	if health <= 0.0:
		_defeat()
	elif phase_count < 2 and health <= threshold:
		_begin_air_phase()


func _defeat() -> void:
	state = State.DEFEATED
	_clear_attacks()
	_enable_body(false)
	_bar.hide()
	_sprite.hide()
	_progress.call("record_defeat")
	combat_changed.emit()
	queue_redraw()


func is_alive() -> bool:
	return state != State.DEFEATED


func is_fighting() -> bool:
	return state != State.WAITING and state != State.DEFEATED


func get_current_health() -> float:
	return health


func get_combat_faction() -> StringName:
	return &"monsters"


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center": Vector2(0, -25.0 - _ground_height), "radius": 20.0, "height": 53.0}


func _draw() -> void:
	if state == State.DEFEATED:
		return
	draw_set_transform(Vector2(0.0, -_ground_height), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, lerpf(23.0, 16.0, _altitude / AIR_HEIGHT), Color(0.12, 0.04, 0.12, 0.53), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
