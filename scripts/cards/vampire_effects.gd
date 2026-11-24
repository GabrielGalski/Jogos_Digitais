extends Node2D

const BAT: Script = preload("res://scripts/cards/midnight_bat.gd")
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const THIRST_COOLDOWN: float = 4.0
const THIRST_HEAL: float = 0.05
const MARK_DURATION: float = 5.0
const MARK_DAMAGE_MULTIPLIER: float = 0.75
const MANTLE_RESET: float = 5.0
const MANTLE_DAMAGE_MULTIPLIER: float = 0.65
const PULSE_HITS: int = 8
const PULSE_TICKS: int = 4
const PULSE_HEAL: float = 0.04
const PROCESSION_COOLDOWN: float = 18.0

var player: Player
var service: Node
var _marked: Node2D
var _mark_generation: int = -1
var _mark_remaining: float = 0.0
var _pulse_ticks_left: int = 0
var _pulse_until_tick: float = 0.0
var _ward_remaining: float = 0.0


func primary_hit(runtime: CardCombatRuntime, attack: CardAttack, target: Node2D) -> void:
	if player.dead or attack.runtime != runtime:
		return
	if attack.mutation_generation == runtime.mutation_generation and runtime.mutation_effect() == MutationCard.CRIMSON_PULSE:
		runtime.crimson_charge = mini(runtime.crimson_charge + 1, PULSE_HITS)
	if attack.infusion_generation != runtime.infusion_generation:
		return
	match attack.infusion_effect:
		InfusionCard.CRYPT_THIRST:
			if player.health < player.max_health * 0.5 and _remaining(runtime, &"I09") <= 0.0:
				runtime.cooldowns[&"I09"] = THIRST_COOLDOWN
				player.heal_fraction(THIRST_HEAL)
		InfusionCard.EXECUTIONER_MARK:
			if not _valid(target):
				return
			if not _has_mark(runtime):
				_marked = target
				_mark_generation = runtime.infusion_generation
			if target == _marked:
				_mark_remaining = MARK_DURATION


func incoming_damage(runtime: CardCombatRuntime, amount: float, source: Node2D, enemy_attack: bool) -> float:
	if enemy_attack and is_instance_valid(source) and _has_mark(runtime) and source == _marked:
		amount *= MARK_DAMAGE_MULTIPLIER
	if enemy_attack and runtime.mutation_effect() == MutationCard.TWILIGHT_MANTLE:
		if _remaining(runtime, &"U09") <= 0.0:
			amount *= MANTLE_DAMAGE_MULTIPLIER
			_ward_remaining = 0.24
		runtime.cooldowns[&"U09"] = MANTLE_RESET
	elif _remaining(runtime, &"U09") > 0.0:
		# Swapping the card away during combat does not interrupt the quiet period.
		runtime.cooldowns[&"U09"] = MANTLE_RESET
	return amount


func activate(runtime: CardCombatRuntime) -> bool:
	match runtime.mutation_effect():
		MutationCard.CRIMSON_PULSE:
			if runtime.crimson_charge < PULSE_HITS or _pulse_ticks_left > 0:
				return false
			runtime.crimson_charge = 0
			_pulse_ticks_left = PULSE_TICKS
			_pulse_until_tick = 1.0
			return true
		MutationCard.MIDNIGHT_PROCESSION:
			if _remaining(runtime, &"U11") > 0.0 or get_child_count() > 0:
				return false
			runtime.cooldowns[&"U11"] = PROCESSION_COOLDOWN
			for index: int in range(4):
				var bat: BAT = BAT.new()
				bat.player = player
				bat.service = service
				bat.angle = TAU * float(index) / 4.0
				bat.search_in = 0.10 + float(index) * 0.16
				bat.position = player.surface_world_position() + Vector2.from_angle(bat.angle) * 12.0
				add_child(bat)
			return true
	return false


func advance(delta: float, runtime: CardCombatRuntime, can_fight: bool) -> void:
	var has_visual_feedback: bool = _mark_remaining > 0.0 or _ward_remaining > 0.0
	_mark_remaining = maxf(0.0, _mark_remaining - delta)
	if not can_fight or not _has_mark(runtime):
		_marked = null
		_mark_remaining = 0.0
	_ward_remaining = maxf(0.0, _ward_remaining - delta)
	if not can_fight or runtime.mutation_effect() != MutationCard.CRIMSON_PULSE:
		_pulse_ticks_left = 0
	elif _pulse_ticks_left > 0:
		_pulse_until_tick -= delta
		while _pulse_until_tick <= 0.0 and _pulse_ticks_left > 0:
			_pulse_ticks_left -= 1
			_pulse_until_tick += 1.0
			player.heal_fraction(PULSE_HEAL)
	if not can_fight or runtime.mutation_effect() != MutationCard.MIDNIGHT_PROCESSION:
		for bat: Node in get_children():
			bat.queue_free()
	if has_visual_feedback:
		queue_redraw()


func prompt(runtime: CardCombatRuntime) -> String:
	match runtime.mutation_effect():
		MutationCard.CRIMSON_PULSE:
			if _pulse_ticks_left > 0:
				return "Pulso Carmesim · Regenerando"
			return "F  Pulso Carmesim  %d/%d" % [runtime.crimson_charge, PULSE_HITS]
		MutationCard.MIDNIGHT_PROCESSION:
			var left: float = _remaining(runtime, &"U11")
			return "F  Cortejo  " + ("%.1fs" % left if left > 0.0 else "Pronto")
	return ""


func _has_mark(runtime: CardCombatRuntime) -> bool:
	return _mark_remaining > 0.0 and _mark_generation == runtime.infusion_generation and is_instance_valid(_marked) and _valid(_marked)


func _valid(enemy: Node2D) -> bool:
	return is_instance_valid(enemy) and bool(service.call("valid_enemy", enemy))


func _remaining(runtime: CardCombatRuntime, key: StringName) -> float:
	return float(runtime.cooldowns.get(key, 0.0))


func _draw() -> void:
	if is_instance_valid(_marked):
		var point: Vector2 = to_local(CONTACTS.damage_center(_marked)) - Vector2(0.0, 10.0)
		draw_colored_polygon(PackedVector2Array([
			point + Vector2(0, -4), point + Vector2(3, 0), point + Vector2(0, 4), point + Vector2(-3, 0)
		]), Color("#f45b7f"))
		draw_circle(point, 1.0, Color("#ffd6bf"))
	if _ward_remaining > 0.0:
		var point: Vector2 = to_local(player.surface_world_position()) + Vector2(0, -3)
		draw_arc(point, 13.0, -PI * 0.37, PI * 1.37, 24, Color(0.75, 0.39, 0.81, _ward_remaining * 3.1), 1.5)
