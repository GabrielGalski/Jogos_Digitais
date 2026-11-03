extends Node
## Caster-local equipment command, input selector and attack cadence for the first six models.

signal weapon_changed(code: StringName, display_name: String)
const FACTORY: Script = preload("res://scripts/combat/manifestations/manifestation_factory.gd")
const IMPACT: Script = preload("res://scripts/visual/weapons/procedural_impact.gd")
const LIGHTING: Script = preload("res://scripts/visual/weapons/procedural_weapon_lighting.gd")
const MODELS: Array[ProceduralManifestationModel] = [
	preload("res://resources/weapons/procedural/M01.tres"),
	preload("res://resources/weapons/procedural/M02.tres"),
	preload("res://resources/weapons/procedural/M04.tres"),
	preload("res://resources/weapons/procedural/M06.tres"),
	preload("res://resources/weapons/procedural/M07.tres"),
	preload("res://resources/weapons/procedural/M08.tres"),
]

var player: Player = null
var gun: Node2D = null
var projectiles: Node2D = null
var reticle: Node2D = null
var sprites: ProceduralWeaponSpriteFactory = ProceduralWeaponSpriteFactory.new()
var lighting: Node2D = null
var selected_index: int = 0
var channel: Node2D = null
var trigger_requested: bool = false
var _infusion_remaining: Dictionary[StringName, float] = {}
var _tick_remaining: Dictionary[StringName, float] = {}
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


func configure(actor: Player, shooter: Node2D, shots: Node2D, cursor: Node2D) -> void:
	player = actor
	gun = shooter
	projectiles = shots
	reticle = cursor
	_random.seed = 16027
	process_physics_priority = 4
	for model: ProceduralManifestationModel in MODELS:
		assert(model.validation_errors().is_empty(), str(model.validation_errors()))
	lighting = LIGHTING.new() as Node2D
	lighting.name = "ProceduralWeaponLighting"
	add_child(lighting)
	lighting.call("configure", sprites)
	player.defeated.connect(cancel_attacks)
	gun.call("set_manifestation_driver", self)
	_sync_equipped_model()
	_update_reticle()


func selected_model() -> ProceduralManifestationModel:
	return MODELS[selected_index]


func select_model(index: int) -> bool:
	if gun == null or index < 0 or index >= MODELS.size():
		return false
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var loadout: CardLoadout = runtime.copy_loadout()
	if loadout == null:
		loadout = (gun.get("initial_loadout") as CardLoadout).duplicate(true) as CardLoadout
	loadout.manifestation = MODELS[index].card
	if not bool(gun.call("equip_cards", loadout)):
		return false
	_stop_channel()
	trigger_requested = false
	selected_index = index
	gun.set("cooldown", 0.0)
	gun.set("require_mouse_release", true)
	_update_reticle()
	weapon_changed.emit(selected_model().code(), selected_model().card.display_name)
	return true


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or player == null or player.dead or player.intro_locked or get_tree().paused:
		return
	if key.physical_keycode != KEY_BACKSPACE and key.keycode != KEY_BACKSPACE:
		return
	select_model((selected_index + 1) % MODELS.size())
	get_viewport().set_input_as_handled()


func set_trigger(requested: bool) -> void:
	trigger_requested = requested


func _can_attack() -> bool:
	return is_instance_valid(player) and not player.dead and not player.intro_locked and not player.is_parry_feedback_active() and bool(gun.get("equipped")) and bool(gun.get("combat_enabled")) and bool(gun.call("is_aim_allowed"))


func _physics_process(delta: float) -> void:
	if gun == null:
		return
	_sync_equipped_model()
	for code: StringName in _infusion_remaining.keys():
		_infusion_remaining[code] = maxf(0.0, _infusion_remaining[code] - delta)
	for code: StringName in _tick_remaining.keys():
		_tick_remaining[code] = maxf(0.0, _tick_remaining[code] - delta)
	var requested: bool = trigger_requested and _can_attack()
	var model: ProceduralManifestationModel = selected_model()
	if model.family == ProceduralManifestationModel.Family.PROJECTILE:
		if requested:
			gun.call("fire_once")
		return
	if requested and not is_instance_valid(channel):
		channel = FACTORY.channel(model, projectiles, player, sprites)
	if not is_instance_valid(channel):
		return
	gun.call("_update_rig", 0.0)
	var muzzle: Marker2D = gun.get_node("WeaponPivot/Muzzle") as Marker2D
	var direction: Vector2 = gun.get("aim_direction") as Vector2
	channel.call("advance", delta, muzzle.global_position, direction, requested)
	if requested:
		_apply_channel_tick(model)
	elif not bool(channel.get("visible")):
		_stop_channel()


func fire_once() -> Node2D:
	if not _can_attack() or float(gun.get("cooldown")) > 0.0:
		return null
	var model: ProceduralManifestationModel = selected_model()
	if model.family != ProceduralManifestationModel.Family.PROJECTILE:
		set_trigger(true)
		return null
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var attack: CardAttack = runtime.create_attack()
	if attack == null:
		return null
	var muzzle: Marker2D = gun.get_node("WeaponPivot/Muzzle") as Marker2D
	var direction: Vector2 = gun.get("aim_direction") as Vector2
	if model.spread_degrees > 0.0:
		direction = direction.rotated(deg_to_rad(_random.randf_range(-model.spread_degrees, model.spread_degrees)))
	var effects: CombatEffects = gun.get("effects") as CombatEffects
	var shot: Node2D = FACTORY.projectile(model, attack, projectiles, muzzle.global_position + direction * 5.0,
		direction, effects, player, sprites)
	shot.connect("impacted", _on_impact)
	gun.set("cooldown", attack.fire_interval)
	_present_shot(model, muzzle.global_position)
	return shot


func _apply_channel_tick(model: ProceduralManifestationModel) -> void:
	var code: StringName = model.code()
	if float(_tick_remaining.get(code, 0.0)) > 0.0:
		return
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var attack: CardAttack = runtime.create_attack()
	if attack == null:
		return
	_tick_remaining[code] = attack.fire_interval
	var infusion_available: bool = float(_infusion_remaining.get(code, 0.0)) <= 0.0 and attack.explosion_damage > 0.0
	if not infusion_available:
		attack.explosion_damage = 0.0
	var targets: Array[Node2D] = channel.call("hit_targets") as Array[Node2D]
	var effects: CombatEffects = gun.get("effects") as CombatEffects
	var direction: Vector2 = channel.get("direction") as Vector2
	var contact: Vector2 = channel.global_position + (channel.get("endpoint") as Vector2)
	for enemy: Node2D in targets:
		attack.apply_primary_hit(enemy, contact if model.family == ProceduralManifestationModel.Family.BEAM else enemy.global_position, direction, effects)
	if not targets.is_empty():
		if infusion_available:
			_infusion_remaining[code] = model.infusion_interval
		var impact_at: Vector2 = contact
		if model.family == ProceduralManifestationModel.Family.STREAM:
			impact_at = targets[0].global_position
			if targets[0].has_method("get_projectile_hurt_capsule"):
				var capsule: Dictionary = targets[0].call("get_projectile_hurt_capsule") as Dictionary
				impact_at = targets[0].to_global(capsule.get("center", Vector2.ZERO) as Vector2)
		_on_impact(impact_at, model, 5.0, direction)
	_present_shot(model, channel.global_position)


func _present_shot(model: ProceduralManifestationModel, origin: Vector2) -> void:
	gun.call("present_procedural_shot")
	lighting.call("flash", origin, model, false)


func _on_impact(at: Vector2, model: ProceduralManifestationModel, radius: float, aim: Vector2) -> void:
	if not is_instance_valid(projectiles):
		return
	var burst: Node2D = IMPACT.new() as Node2D
	burst.name = "ProceduralImpact_" + String(model.code())
	projectiles.add_child(burst)
	burst.global_position = at.round()
	burst.call("configure", model, radius, aim)
	lighting.call("flash", at, model, true)


func _sync_equipped_model() -> void:
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var code: StringName = runtime.manifestation_id()
	for index: int in range(MODELS.size()):
		if MODELS[index].code() == code and selected_index != index:
			selected_index = index
			_stop_channel()
			_update_reticle()
			break


func _update_reticle() -> void:
	if is_instance_valid(reticle):
		reticle.call("set_tint", selected_model().body_color)


func _stop_channel() -> void:
	if is_instance_valid(channel) and not channel.is_queued_for_deletion():
		channel.hide()
		channel.queue_free()
	channel = null


func cancel_attacks() -> void:
	trigger_requested = false
	_stop_channel()
	if is_instance_valid(projectiles):
		for child: Node in projectiles.get_children():
			child.set_physics_process(false)
			child.queue_free()
