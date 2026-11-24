extends Node2D
## Secondary attacks and per-target heat for the Dragon cards.

const METEOR: Script = preload("res://scripts/bosses/dragon/dragon_meteor.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const HEAT_LIMIT: int = 4
const GREED_KILLS: int = 100
const METEOR_RANGE: float = 190.0
const WIND_SPEED: float = 260.0
const WIND_RADIUS: float = 16.0
const WIND_DURATION: float = 0.30

var player: Player
var service: Node2D
var rewards: Node
var _heated_id: int = 0
var _heat_hits: int = 0
var _heat_generation: int = -1
var _winds: Array[Dictionary] = []


func primary_hit(runtime: CardCombatRuntime, attack: CardAttack, enemy: Node2D) -> void:
	if attack.infusion_effect != InfusionCard.EMBER_HEAT or attack.infusion_generation != runtime.infusion_generation:
		return
	if not service.call("valid_enemy", enemy):
		_heat_hits = 0
		_heated_id = 0
		return
	var id: int = enemy.get_instance_id()
	if _heated_id != id or _heat_generation != runtime.infusion_generation:
		_heated_id = id
		_heat_generation = runtime.infusion_generation
		_heat_hits = 0
	_heat_hits += 1
	if _heat_hits < HEAT_LIMIT:
		return
	_heat_hits = 0
	var at: Vector2 = CONTACTS.damage_center(enemy)
	service.call("visual", &"ember_burst", at, 0.22)
	attack.apply_secondary_hit(enemy, maxf(2.0, attack.damage * 0.65), Vector2.ZERO, service.call("effects"))


func enemy_kill(runtime: CardCombatRuntime, attack: CardAttack = null) -> void:
	if player.dead:
		return
	if runtime.mutation_effect() == MutationCard.DRAGON_GREED and (attack == null or attack.mutation_generation == runtime.mutation_generation):
		runtime.dragon_kills += 1
		if runtime.dragon_kills >= GREED_KILLS:
			runtime.dragon_kills -= GREED_KILLS
			rewards.call("queue_random_pack")
	if runtime.infusion_effect() != InfusionCard.DRAGON_METEOR or float(runtime.cooldowns.get(&"I12", 0.0)) > 0.0:
		return
	if attack != null and (attack.infusion_effect != InfusionCard.DRAGON_METEOR or attack.infusion_generation != runtime.infusion_generation):
		return
	var candidates: Array[Node2D] = []
	for enemy: Node2D in service.call("enemies"):
		if player.global_position.distance_squared_to(enemy.global_position) <= METEOR_RANGE * METEOR_RANGE:
			candidates.append(enemy)
	if candidates.is_empty():
		return
	var combat: CombatEffects = service.call("effects")
	var target: Node2D = candidates[combat.random.randi_range(0, candidates.size() - 1)]
	runtime.cooldowns[&"I12"] = runtime.infusion_cooldown()
	var meteor: Node2D = METEOR.new()
	meteor.name = "AlliedDragonMeteor"
	meteor.position = CONTACTS.damage_center(target)
	meteor.set("aimed", true)
	meteor.set("fall_time", 0.52)
	meteor.set("allied_impact", _meteor_impact.bind(attack))
	add_child(meteor)


func _meteor_impact(at: Vector2, radius: float, attack: CardAttack) -> void:
	if player.dead:
		return
	var combat: CombatEffects = service.call("effects")
	for enemy: Node2D in service.call("enemies"):
		var center: Vector2 = CONTACTS.damage_center(enemy)
		if center.distance_squared_to(at) > radius * radius or not _ray(at, center).is_empty():
			continue
		if attack != null:
			attack.apply_secondary_hit(enemy, 12.0, at.direction_to(center), combat)
		else:
			combat.apply_hit(enemy, 12.0, at.direction_to(center), 0.0)


func dash_started() -> void:
	_winds.append({"at": player.surface_world_position(), "direction": player.dash_direction,
		"remaining": WIND_DURATION, "hit": {}})


func advance(delta: float, can_fight: bool) -> void:
	if _winds.is_empty():
		return
	if not can_fight:
		_winds.clear()
	else:
		for index: int in range(_winds.size() - 1, -1, -1):
			if not _advance_wind(_winds[index], delta):
				_winds.remove_at(index)
	queue_redraw()


func _advance_wind(wind: Dictionary, delta: float) -> bool:
	var from: Vector2 = wind.at
	var direction: Vector2 = wind.direction
	var to: Vector2 = from + direction * WIND_SPEED * minf(delta, float(wind.remaining))
	var wall: Dictionary = _ray(from, to)
	if not wall.is_empty():
		to = wall.position
	var hits: Dictionary = wind.hit
	for enemy: Node2D in service.call("enemies"):
		var id: int = enemy.get_instance_id()
		if hits.has(id) or bool(service.call("is_boss", enemy)):
			continue
		var center: Vector2 = CONTACTS.damage_center(enemy)
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(center, from, to)
		if center.distance_squared_to(nearest) > WIND_RADIUS * WIND_RADIUS or not _ray(from, center).is_empty():
			continue
		hits[id] = true
		var combat: CombatEffects = service.call("effects")
		combat.apply_hit(enemy, 4.0, direction, 235.0)
	wind.at = to
	wind.remaining = float(wind.remaining) - delta
	return wall.is_empty() and float(wind.remaining) > 0.0


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	return get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, 1))


func _draw() -> void:
	for wind: Dictionary in _winds:
		var at: Vector2 = to_local(wind.at).round()
		var forward: Vector2 = wind.direction
		var side: Vector2 = forward.orthogonal()
		var alpha: float = minf(1.0, float(wind.remaining) * 8.0)
		for lane: int in range(-2, 3):
			var end: Vector2 = at + side * float(lane * 6) - forward * float(absi(lane) * 3)
			draw_line((end - forward * float(14 - absi(lane) * 3)).round(), end.round(), Color(1.0, 0.73, 0.70, alpha), 1.0)
