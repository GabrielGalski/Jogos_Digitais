extends Node2D
## Scene-owned effects and hazards for Elementais de Calimshan.

const VISUAL: Script = preload("res://scripts/cards/calimshan_visual.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const RUNE_PATH: Script = preload("res://scripts/cards/rune_link_path.gd")
const LIGHTNING_RANGE: float = 150.0
const LIGHTNING_STUN: float = 2.0
const DISCHARGE_RANGE: float = 72.0
const BURN_DURATION: float = 3.0
const BURN_INTERVAL: float = 0.5
const BURN_SPREAD_RANGE: float = 44.0
const ICE_RANGE: float = 140.0
const ICE_RADIUS: float = 27.0
const ICE_WARNING: float = 0.28
const ICE_DURATION: float = 2.2
const FIRE_RADIUS: float = 11.0
const FIRE_SPACING: float = 10.0
const FIRE_LIFETIME: float = 2.0
const RUNE_RESET_RANGE: float = 180.0
const RUNE_WIDTH: float = 5.0
const FLOOR_TOLERANCE: float = 8.0

class Condition extends RefCounted:
	var target: Node2D
	var stun_left: float = 0.0
	var freeze_left: float = 0.0
	var charge_left: float = 0.0
	var charge_attack: CardAttack
	var snow: AnimatedSprite2D
	var burn_left: float = 0.0
	var burn_tick: float = 0.5
	var spread_left: float = -1.0
	var burn_attack: CardAttack
	var smoke: AnimatedSprite2D

class GroundFire extends RefCounted:
	var point: Vector2
	var height: float
	var remaining: float
	var fire: Node2D

var player: Player
var combat: CombatEffects
var _enemies_query: Callable
var _floor_query: Callable
var _height_query: Callable
var _conditions: Dictionary[int, Condition] = {}
var _discharges: Array[Dictionary] = []
var _lightning_variant: int = 0
var _ice_ground: Vector2
var _ice_height: float
var _ice_left: float = 0.0
var _ice_attack: CardAttack
var _fire: Array[GroundFire] = []
var _fire_contacts: Dictionary[int, bool] = {}
var _fire_scan: float = 0.0
var _rune_points: Array[Vector2] = []
var _runes: Array[Sprite2D] = []
var _rune_path: PackedVector2Array = PackedVector2Array()
var _rune_bounds: Rect2
var _rune_notice: String = ""
var _link: VISUAL
var _rune_contacts: Dictionary[int, bool] = {}
var _rune_previous: Dictionary[int, Vector2] = {}


func configure(caster: Player, enemies_query: Callable, floor_query: Callable, height_query: Callable) -> void:
	player = caster
	_enemies_query = enemies_query
	_floor_query = floor_query
	_height_query = height_query


func advance(delta: float, runtime: CardCombatRuntime, active: bool) -> void:
	if not active or not is_instance_valid(combat):
		_clear()
		return
	_tick_conditions(delta)
	_resolve_discharges()
	_tick_ice(delta)
	_tick_fire(delta)
	if runtime.mutation_effect() == MutationCard.PRIMORDIAL_CONVERGENCE:
		_tick_runes()
	elif not _runes.is_empty() or not _rune_notice.is_empty():
		reset_runes()
	match runtime.infusion_effect():
		InfusionCard.LIGHTNING:
			if float(runtime.cooldowns.get(&"I06", 0.0)) <= 0.0:
				_try_lightning(runtime)
		InfusionCard.ICE:
			if _ice_attack == null and float(runtime.cooldowns.get(&"I08", 0.0)) <= 0.0:
				_try_ice(runtime)


func inflict_fire(target: Node2D, attack: CardAttack) -> void:
	if not _targetable(target) or player.dead or float(attack.runtime.cooldowns.get(&"I07", 0.0)) > 0.0:
		return
	attack.runtime.cooldowns[&"I07"] = attack.infusion_cooldown
	_ignite(target, attack, true)


func enemy_defeated(id: int, at: Vector2) -> void:
	var condition: Condition = _conditions.get(id)
	if condition == null or condition.charge_attack == null or condition.charge_left <= 0.0 or player.dead:
		return
	_discharges.append({"at": at, "attack": condition.charge_attack})
	condition.charge_attack = null


func _try_lightning(runtime: CardCombatRuntime) -> void:
	var targets: Array[Node2D] = _nearby(player.surface_world_position(), LIGHTNING_RANGE)
	if targets.is_empty():
		return
	var attack: CardAttack = runtime.create_attack()
	if attack == null:
		return
	var target: Node2D = targets.pick_random() as Node2D
	var at: Vector2 = CONTACTS.damage_center(target)
	var clip: StringName = &"lightning_a" if _lightning_variant == 0 else &"lightning_b"
	_lightning_variant = 1 - _lightning_variant
	VISUAL.play_sprite(self, clip, at, Vector2.ONE, Vector2(0, -28))
	runtime.cooldowns[&"I06"] = attack.infusion_cooldown
	var state: Condition = _condition(target)
	state.charge_left = LIGHTNING_STUN
	state.charge_attack = attack
	if attack.apply_secondary_hit(target, 5.0, Vector2.ZERO, combat):
		if _targetable(target):
			_immobilize(state, LIGHTNING_STUN, false)
	else:
		state.charge_left = 0.0
		state.charge_attack = null


func _resolve_discharges() -> void:
	var pending: Array[Dictionary] = _discharges
	_discharges = []
	for discharge: Dictionary in pending:
		var origin: Vector2 = discharge.at as Vector2
		var attack: CardAttack = discharge.attack as CardAttack
		for target: Node2D in _nearby(origin, DISCHARGE_RANGE):
			if not _targetable(target):
				continue
			var offset: Vector2 = CONTACTS.damage_center(target) - origin
			var arc: AnimatedSprite2D = VISUAL.play_sprite(self, &"discharge", origin,
				Vector2(maxf(8.0, offset.length()) / 64.0, 0.85), Vector2(32, 0))
			arc.rotation = offset.angle()
			attack.apply_secondary_hit(target, 3.0, offset.normalized(), combat)


func _try_ice(runtime: CardCombatRuntime) -> void:
	var candidates: Array[Vector2] = []
	for enemy: Node2D in _nearby(player.surface_world_position(), ICE_RANGE):
		var ground: Vector2 = enemy.global_position
		if _has_floor(ground):
			candidates.append(ground)
	if candidates.is_empty():
		return
	_ice_attack = runtime.create_attack()
	if _ice_attack == null:
		return
	_ice_ground = candidates.pick_random() as Vector2
	_ice_height = _height(_ice_ground)
	_ice_left = ICE_WARNING
	runtime.cooldowns[&"I08"] = _ice_attack.infusion_cooldown


func _tick_ice(delta: float) -> void:
	if _ice_attack == null:
		return
	_ice_left -= delta
	if _ice_left > 0.0:
		return
	var attack: CardAttack = _ice_attack
	_ice_attack = null
	var at: Vector2 = _ice_ground - Vector2(0, _ice_height)
	var spikes: AnimatedSprite2D = VISUAL.play_sprite(self, &"spikes", at, Vector2(1.26, 1.12), Vector2(0, -14))
	spikes.frame = 2
	for enemy: Node2D in _enemies_query.call():
		if not _targetable(enemy):
			continue
		var ground: Vector2 = enemy.global_position
		if ground.distance_squared_to(_ice_ground) <= ICE_RADIUS * ICE_RADIUS \
				and absf(_height(ground) - _ice_height) <= FLOOR_TOLERANCE \
				and attack.apply_secondary_hit(enemy, 3.0, Vector2.ZERO, combat) and _targetable(enemy):
			_immobilize(_condition(enemy), ICE_DURATION, true)


func _condition(target: Node2D) -> Condition:
	var id: int = target.get_instance_id()
	if not _conditions.has(id):
		var state: Condition = Condition.new()
		state.target = target
		_conditions[id] = state
	return _conditions[id]


func _immobilize(state: Condition, duration: float, frozen: bool) -> void:
	state.target.add_to_group(&"immobilized_enemies")
	if frozen:
		state.freeze_left = maxf(state.freeze_left, duration)
		state.target.add_to_group(&"frozen_enemies")
		if not is_instance_valid(state.snow):
			state.snow = VISUAL.play_sprite(self, &"frozen", _above_head(state.target, 7.0), Vector2.ONE * 0.8)
	else:
		state.stun_left = maxf(state.stun_left, duration)


func _ignite(target: Node2D, attack: CardAttack, spreads: bool) -> void:
	var state: Condition = _condition(target)
	if not is_instance_valid(state.smoke):
		state.smoke = VISUAL.play_sprite(target, &"burn", _above_head(target, 9.0), Vector2.ONE * 0.20)
		state.smoke.z_index = -1
		state.burn_tick = BURN_INTERVAL
	state.burn_left = BURN_DURATION
	if attack != null:
		state.burn_attack = attack
	if spreads:
		state.spread_left = 0.45


func _tick_conditions(delta: float) -> void:
	for id: int in _conditions.keys():
		var state: Condition = _conditions[id]
		if not _targetable(state.target):
			_release_condition(state)
			_conditions.erase(id)
			continue
		state.charge_left = maxf(0.0, state.charge_left - delta)
		if state.charge_left <= 0.0:
			state.charge_attack = null
		state.stun_left = maxf(0.0, state.stun_left - delta)
		state.freeze_left = maxf(0.0, state.freeze_left - delta)
		if state.freeze_left <= 0.0 and state.target.is_in_group(&"frozen_enemies"):
			state.target.remove_from_group(&"frozen_enemies")
			if is_instance_valid(state.snow):
				state.snow.queue_free()
			state.snow = null
		elif is_instance_valid(state.snow):
			state.snow.global_position = _above_head(state.target, 7.0).round()
		if state.stun_left <= 0.0 and state.freeze_left <= 0.0 and state.target.is_in_group(&"immobilized_enemies"):
			state.target.remove_from_group(&"immobilized_enemies")
		if state.burn_left > 0.0:
			_tick_burn(state, delta)
		if state.burn_left <= 0.0 and state.freeze_left <= 0.0 and state.stun_left <= 0.0 and state.charge_left <= 0.0:
			_conditions.erase(id)


func _tick_burn(state: Condition, delta: float) -> void:
	if is_instance_valid(state.smoke):
		state.smoke.global_position = _above_head(state.target, 9.0).round()
	if state.spread_left >= 0.0:
		state.spread_left -= delta
		if state.spread_left <= 0.0:
			state.spread_left = -1.0 if _spread_burn(state) else 0.15
	state.burn_tick -= minf(delta, state.burn_left)
	state.burn_left = maxf(0.0, state.burn_left - delta)
	if state.burn_tick <= 0.0001:
		state.burn_tick += BURN_INTERVAL
		if state.burn_attack != null:
			state.burn_attack.apply_secondary_hit(state.target, 1.0, Vector2.ZERO, combat)
		else:
			combat.apply_hit(state.target, 1.0, Vector2.ZERO, 0.0)
	if state.burn_left <= 0.0:
		if is_instance_valid(state.smoke):
			state.smoke.queue_free()
		state.smoke = null
		state.burn_attack = null
		state.spread_left = -1.0


func _spread_burn(state: Condition) -> bool:
	var origin: Vector2 = CONTACTS.damage_center(state.target)
	var neighbors: Array[Node2D] = _nearby(origin, BURN_SPREAD_RANGE)
	neighbors.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return CONTACTS.damage_center(a).distance_squared_to(origin) < CONTACTS.damage_center(b).distance_squared_to(origin))
	var spread_count: int = 0
	for enemy: Node2D in neighbors:
		var other: Condition = _conditions.get(enemy.get_instance_id())
		if enemy == state.target or (other != null and other.burn_left > 0.0):
			continue
		_ignite(enemy, state.burn_attack, false)
		spread_count += 1
		if spread_count == 2:
			break
	return spread_count > 0


func dash_moved(from: Vector2, to: Vector2) -> void:
	if _fire.is_empty() or _fire[-1].point.distance_to(from) > FIRE_SPACING * 1.8:
		_place_fire(from)
	if _fire.is_empty() or _fire[-1].point.distance_to(to) >= FIRE_SPACING:
		_place_fire(to)


func _place_fire(point: Vector2) -> void:
	if not _has_floor(point):
		return
	var patch: GroundFire = GroundFire.new()
	patch.point = point
	patch.height = _height(point)
	patch.remaining = FIRE_LIFETIME
	patch.fire = _ground_visual(VISUAL.Kind.GROUND_FIRE, point, patch.height, FIRE_LIFETIME, FIRE_RADIUS)
	_fire.append(patch)
	if _fire.size() > 28:
		var oldest: GroundFire = _fire.pop_front()
		if is_instance_valid(oldest.fire):
			oldest.fire.queue_free()


func _tick_fire(delta: float) -> void:
	for index: int in range(_fire.size() - 1, -1, -1):
		_fire[index].remaining -= delta
		if _fire[index].remaining <= 0.0:
			if is_instance_valid(_fire[index].fire):
				_fire[index].fire.queue_free()
			_fire.remove_at(index)
	if _fire.is_empty():
		_fire_contacts.clear()
		return
	_fire_scan -= delta
	if _fire_scan > 0.0:
		return
	_fire_scan = 0.06
	var inside: Dictionary[int, bool] = {}
	for enemy: Node2D in _enemies_query.call():
		if not _targetable(enemy):
			continue
		for patch: GroundFire in _fire:
			if enemy.global_position.distance_squared_to(patch.point) > FIRE_RADIUS * FIRE_RADIUS \
					or absf(_height(enemy.global_position) - patch.height) > FLOOR_TOLERANCE:
				continue
			var id: int = enemy.get_instance_id()
			inside[id] = true
			if not _fire_contacts.has(id) and combat.apply_hit(enemy, 2.0, Vector2.ZERO, 0.0) and _targetable(enemy):
				_ignite(enemy, null, false)
			break
	_fire_contacts = inside


func activate_rune() -> bool:
	_rune_notice = ""
	if _runes.size() == 2:
		reset_runes()
		return true
	var point: Vector2 = player.to_global(Vector2(0, 3))
	if not _has_floor(point):
		_rune_notice = "F  Coloque a runa em chão firme"
		return false
	if not _rune_points.is_empty() and _rune_points[0].distance_to(point) > RUNE_RESET_RANGE:
		reset_runes()
	if not _runes.is_empty():
		_rune_path = _route_second_rune(point)
		if _rune_path.is_empty():
			_rune_notice = "F  Sem caminho. Tente outro ponto"
			return false
		point = _rune_path[-1]
	_rune_points.append(point)
	_runes.append(VISUAL.place_rune(self, point - Vector2(0, _height(point)), _runes.size()))
	if _runes.size() == 2:
		_draw_rune_path()
	return true


func _route_second_rune(point: Vector2) -> PackedVector2Array:
	var first: Vector2 = _rune_points[0]
	var route: RUNE_PATH = RUNE_PATH.new(get_world_2d(), _floor_query, player.get_rid())
	if first.distance_squared_to(point) >= 4.0:
		return route.find(first, point, RUNE_RESET_RANGE)
	# Two presses from the same spot still produce a short beam in front of Nox.
	var direction: Vector2 = player.body.facing.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	for turn: float in [0.0, PI * 0.5, -PI * 0.5, PI]:
		var adjacent: Vector2 = first + direction.rotated(turn) * 12.0
		if route.segment_clear(first, adjacent):
			return PackedVector2Array([first, adjacent])
	return PackedVector2Array()


func _draw_rune_path() -> void:
	_rune_bounds = Rect2(_rune_path[0], Vector2.ZERO)
	for point: Vector2 in _rune_path:
		_rune_bounds = _rune_bounds.expand(point)
	_rune_bounds = _rune_bounds.grow(RUNE_WIDTH)
	_link = VISUAL.new()
	_link.name = "PrimordialLightning"
	_link.kind = VISUAL.Kind.RUNE_LINK
	_link.position = _runes[0].position
	var projected: PackedVector2Array = RUNE_PATH.project(_rune_path, _height_query)
	for point: Vector2 in projected:
		_link.lightning_path.append(point.round() - _link.position)
	add_child(_link)


func rune_count() -> int:
	return _runes.size()


func rune_prompt() -> String:
	if not _rune_notice.is_empty():
		return _rune_notice
	return "F  Desarmar runas" if _runes.size() == 2 else "F  Colocar runa %d/2" % (_runes.size() + 1)


func _tick_runes() -> void:
	var feet: Vector2 = player.to_global(Vector2(0, 3))
	for point: Vector2 in _rune_points:
		if feet.distance_squared_to(point) > RUNE_RESET_RANGE * RUNE_RESET_RANGE:
			reset_runes()
			return
	if _runes.size() != 2:
		return
	var inside: Dictionary[int, bool] = {}
	var previous: Dictionary[int, Vector2] = {}
	for enemy: Node2D in _enemies_query.call():
		if not _targetable(enemy):
			continue
		var point: Vector2 = enemy.global_position
		var id: int = enemy.get_instance_id()
		previous[id] = point
		var touches: bool = _rune_intersects(point, point)
		if touches:
			inside[id] = true
		if _rune_contacts.has(id):
			continue
		var old_position: Vector2 = _rune_previous.get(id, point) as Vector2
		var contact: bool = touches or (old_position != point and _rune_intersects(old_position, point))
		if contact and combat.apply_hit(enemy, 6.0, Vector2.ZERO, 0.0) and _targetable(enemy):
			_immobilize(_condition(enemy), 1.25, false)
	_rune_contacts = inside
	_rune_previous = previous


func _rune_intersects(from: Vector2, to: Vector2) -> bool:
	var motion_bounds: Rect2 = Rect2(from, Vector2.ZERO).expand(to)
	if not _rune_bounds.intersects(motion_bounds, true):
		return false
	for index: int in range(1, _rune_path.size()):
		var pair: PackedVector2Array = Geometry2D.get_closest_points_between_segments(from, to, _rune_path[index - 1], _rune_path[index])
		if pair[0].distance_squared_to(pair[1]) <= RUNE_WIDTH * RUNE_WIDTH \
				and absf(_height(pair[0]) - _height(pair[1])) <= FLOOR_TOLERANCE:
			return true
	return false


func reset_runes() -> void:
	for rune: Sprite2D in _runes:
		if is_instance_valid(rune):
			rune.queue_free()
	if is_instance_valid(_link):
		_link.queue_free()
	_link = null
	_rune_points.clear()
	_runes.clear()
	_rune_path.clear()
	_rune_notice = ""
	_rune_contacts.clear()
	_rune_previous.clear()


func _ground_visual(kind: int, point: Vector2, height: float, lifetime: float, radius: float) -> VISUAL:
	var visual: VISUAL = VISUAL.new()
	visual.kind = kind
	visual.lifetime = lifetime
	visual.radius = radius
	visual.position = (point - Vector2(0, height)).round()
	add_child(visual)
	return visual


func _above_head(enemy: Node2D, gap: float) -> Vector2:
	var half_height: float = 9.0
	if enemy.has_method("get_projectile_hurt_capsule"):
		var capsule: Dictionary = enemy.call("get_projectile_hurt_capsule") as Dictionary
		half_height = float(capsule.get("height", 18.0)) * 0.5
	return CONTACTS.damage_center(enemy) - Vector2(0, half_height + gap)


func _nearby(at: Vector2, radius: float) -> Array[Node2D]:
	var targets: Array[Node2D] = []
	for enemy: Node2D in _enemies_query.call():
		if _targetable(enemy) and CONTACTS.damage_center(enemy).distance_squared_to(at) <= radius * radius:
			targets.append(enemy)
	return targets


func _targetable(enemy: Node2D) -> bool:
	return is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_in_group(&"controlled_monsters") \
		and not enemy.is_in_group(&"sound_fields") and bool(enemy.call("is_alive"))


func _has_floor(point: Vector2) -> bool:
	return bool(_floor_query.call(point))


func _height(point: Vector2) -> float:
	return float(_height_query.call(point))


func _release_condition(state: Condition) -> void:
	if is_instance_valid(state.target):
		for group: StringName in [&"immobilized_enemies", &"frozen_enemies"]:
			if state.target.is_in_group(group):
				state.target.remove_from_group(group)
	if is_instance_valid(state.smoke):
		state.smoke.queue_free()
	if is_instance_valid(state.snow):
		state.snow.queue_free()


func _clear() -> void:
	for state: Condition in _conditions.values():
		_release_condition(state)
	_conditions.clear()
	_discharges.clear()
	_ice_attack = null
	_fire.clear()
	_fire_contacts.clear()
	reset_runes()
	for visual: Node in get_children():
		visual.queue_free()


func _exit_tree() -> void:
	for state: Condition in _conditions.values():
		_release_condition(state)
