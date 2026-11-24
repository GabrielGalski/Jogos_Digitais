extends Node
## Caster-local equipment, paused card selection and shared attack cadence.

signal weapon_changed(code: StringName, display_name: String)
signal equipment_menu_closed
const FACTORY: Script = preload("res://scripts/combat/manifestations/manifestation_factory.gd")
const IMPACT: Script = preload("res://scripts/visual/weapons/procedural_impact.gd")
const LIGHTING: Script = preload("res://scripts/visual/weapons/procedural_weapon_lighting.gd")
const EQUIPMENT: PackedScene = preload("res://scenes/cards/equipment_menu.tscn")
const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const MODELS: Array[ProceduralManifestationModel] = CATALOG.MANIFESTATIONS

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
var _equipment_menu: CanvasLayer = null
var _spiral_step: int = 0


func configure(actor: Player, shooter: Node2D, shots: Node2D, cursor: Node2D) -> void:
	player = actor
	gun = shooter
	projectiles = shots
	reticle = cursor
	add_to_group(&"manifestation_controllers")
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


func available_models() -> Array[ProceduralManifestationModel]:
	return MODELS


func select_infusion(index: int) -> bool:
	if index < -1 or index >= CATALOG.INFUSIONS.size():
		return false
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var loadout: CardLoadout = runtime.copy_loadout()
	loadout.infusion = CATALOG.INFUSIONS[index] if index >= 0 else null
	suspend_trigger()
	return bool(gun.call("equip_cards", loadout))


func select_mutation(index: int) -> bool:
	if index < -1 or index >= CATALOG.MUTATIONS.size():
		return false
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var loadout: CardLoadout = runtime.copy_loadout()
	loadout.mutation = CATALOG.MUTATIONS[index] if index >= 0 else null
	suspend_trigger()
	return bool(gun.call("equip_cards", loadout))


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
	gun.call("clear_muzzle_effect")
	_update_reticle()
	weapon_changed.emit(selected_model().code(), selected_model().card.display_name)
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or (key.keycode != KEY_I and key.physical_keycode != KEY_I):
		return
	if get_tree().get_first_node_in_group(&"card_table_modal") == null and open_equipment_menu():
		get_viewport().set_input_as_handled()


func open_equipment_menu() -> bool:
	if not is_instance_valid(player) or player.dead or player.intro_locked or get_tree().paused or is_instance_valid(_equipment_menu):
		return false
	_sync_equipped_model()
	suspend_trigger()
	_equipment_menu = EQUIPMENT.instantiate() as CanvasLayer
	_equipment_menu.set("controller", self)
	_equipment_menu.tree_exited.connect(_on_equipment_menu_closed, CONNECT_ONE_SHOT)
	get_tree().current_scene.add_child(_equipment_menu)
	return true


func _on_equipment_menu_closed() -> void:
	_equipment_menu = null
	equipment_menu_closed.emit()


func suspend_trigger() -> void:
	trigger_requested = false
	_stop_channel()
	gun.set("require_mouse_release", true)
	gun.call("clear_muzzle_effect")


func set_trigger(requested: bool) -> void:
	trigger_requested = requested


func _can_attack() -> bool:
	return is_instance_valid(player) and not player.dead and not player.intro_locked and not player.mutation_invisible and not player.is_parry_feedback_active() and bool(gun.get("equipped")) and bool(gun.get("combat_enabled")) and bool(gun.call("is_aim_allowed"))


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
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	channel.call("advance", delta, muzzle.global_position, direction, requested, runtime.infusion_effect() == InfusionCard.GARGOYLE)
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
	if model.projectile_count == 1 and model.spread_degrees > 0.0:
		direction = direction.rotated(deg_to_rad(_random.randf_range(-model.spread_degrees, model.spread_degrees)))
	var effects: CombatEffects = gun.get("effects") as CombatEffects
	var shot: Node2D = _emit_projectiles(model, attack, muzzle.global_position, direction, effects)
	gun.set("cooldown", attack.fire_interval)
	_present_shot(model, muzzle.global_position)
	return shot


func _emit_projectiles(model: ProceduralManifestationModel, attack: CardAttack, muzzle: Vector2,
		direction: Vector2, effects: CombatEffects) -> Node2D:
	var count: int = model.projectile_count
	var center_index: int = floori(float(count) * 0.5)
	var center: Node2D
	attack.separate_projectile_hits = count > 1
	for index: int in range(count):
		var lane: float = float(index - center_index) / float(maxi(center_index, 1))
		if count == 2:
			lane = -1.0 if index == 0 else 1.0
		var angle: float = model.spread_degrees * lane
		var spiral: float = 0.0
		if model.spiral_turn_rate > 0.0:
			spiral = sin(float(_spiral_step) * TAU / 7.0)
			_spiral_step = (_spiral_step + 1) % 7
			angle += spiral * 8.0
		if model.randomize_spread:
			angle = _random.randf_range(-model.spread_degrees, model.spread_degrees)
		var aim: Vector2 = direction.rotated(deg_to_rad(angle))
		var origin: Vector2 = muzzle + direction * (5.0 - absf(lane) * 2.0)
		origin += direction.orthogonal() * lane * model.muzzle_spread
		if model.cross_distance > 0.0:
			aim = origin.direction_to(muzzle + direction * model.cross_distance)
		var projectile: Node2D = FACTORY.projectile(model, attack, projectiles, origin, aim, effects, player, sprites)
		projectile.set("turn_rate", spiral * model.spiral_turn_rate)
		projectile.connect("impacted", _on_impact)
		if model.split_distance > 0.0:
			projectile.connect("split_reached", _emit_split_shards.bind(model, attack, effects), CONNECT_ONE_SHOT)
		if index == center_index:
			center = projectile
	return center


func _emit_split_shards(at: Vector2, direction: Vector2, lifetime: float, model: ProceduralManifestationModel,
		attack: CardAttack, effects: CombatEffects) -> void:
	if not is_instance_valid(projectiles) or not is_instance_valid(effects):
		return
	attack.separate_projectile_hits = true
	_on_impact(at, model, 4.0, direction)
	for side: float in [-1.0, 1.0]:
		var aim: Vector2 = direction.rotated(side * deg_to_rad(model.split_half_angle_degrees))
		var shard: Node2D = FACTORY.projectile(model, attack, projectiles, at, aim, effects, player, sprites)
		shard.call("configure_split_shard", lifetime)
		shard.connect("impacted", _on_impact)


func _apply_channel_tick(model: ProceduralManifestationModel) -> void:
	var code: StringName = model.code()
	if float(_tick_remaining.get(code, 0.0)) > 0.0:
		return
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var attack: CardAttack = runtime.create_attack()
	if attack == null:
		return
	channel.call("set_element", attack.element)
	_tick_remaining[code] = attack.fire_interval
	var infusion_available: bool = float(_infusion_remaining.get(code, 0.0)) <= 0.0 and attack.explosion_damage > 0.0
	if not infusion_available:
		attack.explosion_damage = 0.0
	var targets: Array[Node2D] = channel.call("hit_targets") as Array[Node2D]
	var effects: CombatEffects = gun.get("effects") as CombatEffects
	var contact: Vector2 = channel.global_position + (channel.get("endpoint") as Vector2)
	for enemy: Node2D in targets:
		var direction: Vector2 = channel.call("hit_direction", enemy)
		attack.apply_primary_hit(enemy, contact if model.family == ProceduralManifestationModel.Family.BEAM else effects.CONTACTS.damage_center(enemy), direction, effects)
	if not targets.is_empty():
		if infusion_available:
			_infusion_remaining[code] = model.infusion_interval
		var impact_at: Vector2 = contact
		if model.family == ProceduralManifestationModel.Family.STREAM:
			impact_at = targets[0].global_position
			if targets[0].has_method("get_projectile_hurt_capsule"):
				var capsule: Dictionary = targets[0].call("get_projectile_hurt_capsule") as Dictionary
				impact_at = targets[0].to_global(capsule.get("center", Vector2.ZERO) as Vector2)
		_on_impact(impact_at, model, 5.0, channel.call("hit_direction", targets[0]))
	_present_shot(model, channel.global_position)


func _present_shot(model: ProceduralManifestationModel, origin: Vector2) -> void:
	gun.call("present_procedural_shot", model.body_color, model.family == ProceduralManifestationModel.Family.PROJECTILE)
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
