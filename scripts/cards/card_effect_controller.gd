extends Node2D
## Scene-local card execution. Snapshots retain damage ownership across equipment changes.
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const VISUAL: Script = preload("res://scripts/cards/card_effect_visual.gd")
const FRAGMENT: Script = preload("res://scripts/cards/card_fragment.gd")
const SNAKE: Script = preload("res://scripts/cards/medusa_snake.gd")
const CONTROL: Script = preload("res://scripts/cards/temporary_enemy_control.gd")
const HERO_SWORD: Script = preload("res://scripts/cards/hero_sword.gd")
const CALIMSHAN: Script = preload("res://scripts/cards/calimshan_effects.gd")
const VAMPIRE: Script = preload("res://scripts/cards/vampire_effects.gd")
const DRAGON: Script = preload("res://scripts/cards/dragon_effects.gd")
const BITE_RADIUS: float = 28.0
const GOLEM_IMPACT_DELAY: float = 0.04
var player: Player
var gun: Node2D
var runtime: CardCombatRuntime
var poisons: Dictionary = {}
var blasts: Array[Dictionary] = []
var mouths: Array[Dictionary] = []
var invisible_remaining: float = 0.0
var decoy: Node2D
var _hosts: Array[CONTROL] = []
var _hero_sword: HERO_SWORD
var _calimshan: CALIMSHAN
var _vampire: VAMPIRE
var _dragon: DRAGON
var _kill_source: CombatEffects
var _blast_elapsed: float = 0.0
var _navigation: EnemyNavigationGrid
var _navigation_bounds: Rect2
var _status: Label
var _status_layer: CanvasLayer
var _was_invisible: bool = false
var _body_alpha: float = 1.0
var _gun_visible: bool = true


func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	add_to_group(&"card_effect_controllers")
	process_physics_priority = 2
	player.card_effects = self
	player.damage_received.connect(_on_damage_received)
	player.dash_moved.connect(_on_dash_moved)
	player.dash_started.connect(_on_dash_started)
	_calimshan = CALIMSHAN.new()
	_calimshan.name = "Calimshan"
	_calimshan.configure(player, enemies, has_floor, height_at)
	add_child(_calimshan)
	_vampire = VAMPIRE.new()
	_vampire.name = "VampireEffects"
	_vampire.player = player
	_vampire.service = self
	add_child(_vampire)
	_dragon = DRAGON.new()
	_dragon.name = "DragonEffects"
	_dragon.player = player
	_dragon.service = self
	_dragon.rewards = get_node("/root/BoosterRewards")
	_dragon.z_index = 3
	add_child(_dragon)
	_bind_runtime()
	_status_layer = CanvasLayer.new()
	_status_layer.layer = 55
	add_child(_status_layer)
	_status = Label.new()
	_status.add_theme_font_override("font", preload("res://assets/font/determination.ttf"))
	_status.add_theme_font_size_override("font_size", 11)
	_status_layer.add_child(_status)


func _bind_runtime() -> void:
	runtime = gun.get("card_runtime") as CardCombatRuntime
	runtime.effect_host = weakref(self)
	var source: CombatEffects = effects()
	if source != _kill_source:
		if is_instance_valid(_kill_source):
			_kill_source.enemy_eliminated.disconnect(_on_enemy_eliminated)
			_kill_source.enemy_defeated.disconnect(_calimshan.enemy_defeated)
		_kill_source = source
		_calimshan.combat = source
		if is_instance_valid(_kill_source):
			_kill_source.enemy_eliminated.connect(_on_enemy_eliminated)
			_kill_source.enemy_defeated.connect(_calimshan.enemy_defeated)


func effects() -> CombatEffects:
	return gun.get("effects") as CombatEffects


func _physics_process(delta: float) -> void:
	_bind_runtime()
	invisible_remaining = maxf(0.0, invisible_remaining - delta)
	player.mutation_invisible = invisible_remaining > 0.0
	if player.dead:
		poisons.clear()
		blasts.clear()
		mouths.clear()
		_release_hosts()
		for node: Node in get_children():
			if node is SNAKE:
				node.queue_free()
	if _was_invisible and not player.mutation_invisible:
		player.body.self_modulate.a = _body_alpha
		gun.visible = _gun_visible
		_was_invisible = false
	var kind: int = runtime.mutation_effect()
	var can_fight: bool = not player.dead and not player.intro_locked and bool(gun.get("combat_enabled"))
	_calimshan.advance(delta, runtime, can_fight)
	_vampire.advance(delta, runtime, can_fight)
	_dragon.advance(delta, can_fight)
	_update_hero_sword(can_fight and kind == MutationCard.HERO_SWORD, delta)
	if not can_fight:
		_status.hide()
		return
	_tick_poison(delta)
	_drain_blasts(delta)
	_tick_mouths(delta)
	if kind == 2 and float(runtime.cooldowns.get(&"U03", 0.0)) <= 0.0:
		runtime.cooldowns[&"U03"] = 2.0
		var target: Node2D = nearest_enemy(player.global_position, 180.0)
		if target != null:
			var ground: Vector2 = target.global_position
			if has_floor(ground):
				var at: Vector2 = ground - Vector2(0, height_at(ground))
				visual(&"warning", at, VISUAL.BITE_WINDUP, BITE_RADIUS)
				mouths.append({"at": at, "remaining": VISUAL.BITE_WINDUP})
	var vampire_prompt: String = _vampire.prompt(runtime)
	_status.visible = not vampire_prompt.is_empty() or kind in [3, 5, MutationCard.PRIMORDIAL_CONVERGENCE]
	_status.position = Vector2(10, get_viewport_rect().size.y - 17.0)
	if not vampire_prompt.is_empty():
		_status.text = vampire_prompt
	elif kind == MutationCard.PRIMORDIAL_CONVERGENCE:
		_status.text = _calimshan.rune_prompt()
	elif _status.visible:
		var left: float = float(runtime.cooldowns.get(&"U04" if kind == 3 else &"U06", 0.0))
		_status.text = ("F  Mandragora" if kind == 3 else "F  Doppelganger") + ("  %.1fs" % left if left > 0.0 else "  Pronto")
	var packs: int = int(_dragon.rewards.call("pending_count"))
	if packs > 0:
		var prompt: String = "B  Abrir booster (%d)" % packs
		_status.text = _status.text + "   " + prompt if _status.visible else prompt
		_status.show()


func _update_hero_sword(active: bool, delta: float) -> void:
	if not active:
		if is_instance_valid(_hero_sword):
			_hero_sword.hide()
			_hero_sword.queue_free()
			_hero_sword = null
		return
	if not is_instance_valid(_hero_sword) or _hero_sword.is_queued_for_deletion():
		_hero_sword = HERO_SWORD.new()
		_hero_sword.name = "HeroSword"
		_hero_sword.player = player
		_hero_sword.effects = effects()
		add_child(_hero_sword)
	_hero_sword.advance(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_B or key.physical_keycode == KEY_B:
		if _dragon.rewards.call("open_pending", player):
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F or key.physical_keycode == KEY_F:
		if activate_mutation():
			get_viewport().set_input_as_handled()


func activate_mutation() -> bool:
	_bind_runtime()
	if get_tree().paused or player.dead or player.intro_locked or not bool(gun.get("combat_enabled")):
		return false
	var kind: int = runtime.mutation_effect()
	if kind in [MutationCard.CRIMSON_PULSE, MutationCard.MIDNIGHT_PROCESSION]:
		return _vampire.activate(runtime)
	if kind == MutationCard.PRIMORDIAL_CONVERGENCE:
		return _calimshan.activate_rune()
	if kind == 3 and float(runtime.cooldowns.get(&"U04", 0.0)) <= 0.0:
		runtime.cooldowns[&"U04"] = 4.0
		var popup: VISUAL = visual(&"mandrake", player.surface_world_position() - Vector2(0, 32), 0.65)
		popup.follow = player
		var pushed: bool = false
		for enemy: Node2D in enemies():
			if not enemy is CharacterBody2D or is_boss(enemy) or enemy.global_position.distance_to(player.global_position) > 110.0:
				continue
			var away: Vector2 = player.global_position.direction_to(enemy.global_position)
			if away.is_zero_approx():
				away = player.body.facing.normalized()
			var actor: CharacterBody2D = enemy as CharacterBody2D
			for step: int in range(6):
				var motion: Vector2 = away * 3.0
				if not has_floor(actor.global_position + motion) or actor.move_and_collide(motion) != null:
					break
			if actor.has_method("receive_impact"):
				actor.call("receive_impact", away, 300.0)
			pushed = true
		if pushed:
			visual(&"shockwave", player.surface_world_position(), 0.22, 110.0)
		return true
	if kind == 5 and float(runtime.cooldowns.get(&"U06", 0.0)) <= 0.0:
		_doppelganger()
		return true
	return false


func _on_dash_moved(from: Vector2, to: Vector2) -> void:
	if runtime.mutation_effect() == MutationCard.ASH_STEP and not player.dead and bool(gun.get("combat_enabled")):
		_calimshan.dash_moved(from, to)


func _on_dash_started() -> void:
	if runtime.mutation_effect() == MutationCard.CRIMSON_WINGS and not player.dead and bool(gun.get("combat_enabled")):
		_dragon.dash_started()


func inflict_fire(target: Node2D, attack: CardAttack) -> void:
	_calimshan.inflict_fire(target, attack)


func weapon_hit(attack: CardAttack, target: Node2D) -> void:
	_vampire.primary_hit(runtime, attack, target)
	_dragon.primary_hit(runtime, attack, target)


func adjust_incoming_damage(amount: float, source: Node2D, enemy_attack: bool) -> float:
	_bind_runtime()
	return _vampire.incoming_damage(runtime, amount, source, enemy_attack)


func prevent_death() -> bool:
	_bind_runtime()
	if runtime.mutation_effect() != 5 or float(runtime.cooldowns.get(&"U06", 0.0)) > 0.0:
		return false
	_doppelganger()
	return true


func _doppelganger() -> void:
	runtime.cooldowns[&"U06"] = 30.0
	invisible_remaining = 1.5
	player.mutation_invisible = true
	_body_alpha = player.body.self_modulate.a
	_gun_visible = gun.visible
	player.body.self_modulate.a = _body_alpha * 0.35
	gun.hide()
	_was_invisible = true
	gun.call("clear_muzzle_effect")
	if is_instance_valid(gun.get("manifestation_driver")):
		(gun.get("manifestation_driver") as Node).call("cancel_attacks")
	var copy: VISUAL = VISUAL.new()
	copy.kind = &"copy"
	copy.lifetime = 1.5
	copy.position = player.global_position
	copy.copy_texture = player.body.sprite_frames.get_frame_texture(player.body.animation, player.body.frame)
	copy.copy_offset = player.body.position + player.body.offset
	copy.copy_scale = player.body.scale
	copy.copy_flip = player.body.flip_h
	add_child(copy)
	decoy = copy
	player.dash_from_decoy()
	for enemy: Node2D in enemies():
		if enemy is CharacterBody2D and not is_boss(enemy) and not enemy.has_meta(&"card_control") and enemy.global_position.distance_to(player.global_position) < 220.0:
			var lure: CONTROL = CONTROL.new()
			lure.service = self
			lure.parasite = false
			lure.decoy = decoy
			lure.duration = 1.5
			enemy.add_child(lure)


func _on_damage_received(_amount: float) -> void:
	_bind_runtime()
	if player.dead or not player.last_damage_enemy or runtime.mutation_effect() != 1 or float(runtime.cooldowns.get(&"U02", 0.0)) > 0.0:
		return
	runtime.cooldowns[&"U02"] = 1.5
	if get_tree().get_nodes_in_group(&"medusa_snakes").size() >= 6:
		return
	var snake: SNAKE = SNAKE.new()
	snake.service = self
	snake.position = player.global_position
	snake.target = player.last_damage_source if is_instance_valid(player.last_damage_source) and valid_enemy(player.last_damage_source) else nearest_enemy(player.global_position, 300.0)
	add_child(snake)


func weapon_kill(attack: CardAttack, at: Vector2, impact: Vector2, damage: float, depth: int) -> void:
	if player.dead:
		return
	_dragon.enemy_kill(runtime, attack)
	match attack.infusion_effect:
		InfusionCard.GOLEM:
			_queue_golem_blast(attack, at, depth)
		1:
			var available: int = 24 - get_tree().get_nodes_in_group(&"card_fragments").size()
			for index: int in range(clampi(available, 0, 6)):
				var fragment: FRAGMENT = FRAGMENT.new()
				fragment.attack = attack
				fragment.effects = effects()
				fragment.damage = damage * 0.15
				fragment.speed = 250.0
				fragment.remaining = 0.4
				fragment.direction = Vector2.from_angle(TAU * float(index) / 6.0)
				fragment.position = impact
				add_child(fragment)
		2:
			if attack.infusion_generation == runtime.infusion_generation:
				player.heal_fraction(0.03)


func _on_enemy_eliminated(at: Vector2) -> void:
	_dragon.enemy_kill(runtime)
	if player.dead or runtime.infusion_effect() != InfusionCard.GOLEM:
		return
	var attack: CardAttack = runtime.create_attack()
	if attack != null:
		_queue_golem_blast(attack, at, 0)


func _queue_golem_blast(attack: CardAttack, at: Vector2, depth: int) -> void:
	visual(&"blast", at, 0.4, attack.explosion_radius)
	blasts.append({"attack": attack, "at": at, "depth": depth, "impact_time": _blast_elapsed + GOLEM_IMPACT_DELAY})


func _drain_blasts(delta: float) -> void:
	_blast_elapsed += delta
	if blasts.is_empty() or float(blasts[0].impact_time) > _blast_elapsed:
		return
	var candidates: Array[Node2D] = enemies()
	var processed: int = 0
	while not blasts.is_empty() and processed < 64 and float(blasts[0].impact_time) <= _blast_elapsed:
		processed += 1
		var blast: Dictionary = blasts.pop_front()
		var attack: CardAttack = blast.attack as CardAttack
		var depth: int = int(blast.depth)
		var damage: float = 18.0 if depth == 0 else 9.0 if depth == 1 else 3.0
		var center: Vector2 = blast.at as Vector2
		var radius_squared: float = attack.explosion_radius * attack.explosion_radius
		for enemy: Node2D in candidates:
			if not is_instance_valid(enemy) or not valid_enemy(enemy):
				continue
			var at: Vector2 = CONTACTS.damage_center(enemy)
			if at.distance_squared_to(center) <= radius_squared:
				attack.apply_secondary_hit(enemy, damage, center.direction_to(at), effects(), depth + 1)


func poison(target: Node2D, dps: float, duration: float, attack: CardAttack = null) -> void:
	if not valid_enemy(target):
		return
	var id: int = target.get_instance_id()
	if not poisons.has(id):
		poisons[id] = {"target": target, "tick": 0.5, "sources": {}}
	var sources: Dictionary = poisons[id].sources
	var key: String = "weapon_%d" % attack.infusion_generation if attack != null else "mutation"
	sources[key] = {"amount": dps, "remaining": duration, "attack": attack}


func _tick_poison(delta: float) -> void:
	for id: int in poisons.keys():
		var record: Dictionary = poisons[id]
		if not is_instance_valid(record.target):
			poisons.erase(id)
			continue
		var target: Node2D = record.target as Node2D
		if not valid_enemy(target):
			poisons.erase(id)
			continue
		var best: Dictionary = {}
		var sources: Dictionary = record.sources
		for key: String in sources.keys():
			var source: Dictionary = sources[key]
			source.remaining = float(source.remaining) - delta
			if float(source.remaining) <= 0.0:
				sources.erase(key)
			elif best.is_empty() or float(source.amount) > float(best.amount):
				best = source
		if best.is_empty():
			poisons.erase(id)
			continue
		record.tick = float(record.tick) - delta
		if float(record.tick) <= 0.0:
			record.tick = 0.5
			var attack: CardAttack = best.attack as CardAttack
			if attack != null:
				attack.apply_secondary_hit(target, float(best.amount) * 0.5, Vector2.ZERO, effects())
			else:
				mutation_hit(target, float(best.amount) * 0.5)


func _tick_mouths(delta: float) -> void:
	for index: int in range(mouths.size() - 1, -1, -1):
		var mouth: Dictionary = mouths[index]
		mouth.remaining = float(mouth.remaining) - delta
		if float(mouth.remaining) <= 0.0:
			var at: Vector2 = mouth.at as Vector2
			visual(&"mouth", at, VISUAL.BITE_RECOVERY, BITE_RADIUS)
			for enemy: Node2D in enemies():
				if CONTACTS.damage_center(enemy).distance_to(at) <= BITE_RADIUS:
					mutation_hit(enemy, 6.0)
			mouths.remove_at(index)


func attach_slaad(enemy: Node2D) -> bool:
	if not valid_enemy(enemy) or is_boss(enemy) or not enemy is CharacterBody2D or enemy.has_meta(&"card_control"):
		return false
	var control: CONTROL = CONTROL.new()
	control.service = self
	_hosts.append(control)
	control.tree_exiting.connect(func() -> void: _hosts.erase(control), CONNECT_ONE_SHOT)
	enemy.add_child(control)
	return true


func expire_slaad(enemy: CharacterBody2D) -> void:
	enemy.remove_from_group(&"controlled_monsters")
	if enemy.has_method("get_current_health"):
		effects().apply_hit(enemy, float(enemy.call("get_current_health")), Vector2.ZERO, 0.0)


func _release_hosts() -> void:
	for control: CONTROL in _hosts:
		if is_instance_valid(control):
			control.queue_free()
	_hosts.clear()


func controlled_attack(enemy: Node2D, target: Node2D) -> void:
	if get_tree().get_nodes_in_group(&"card_fragments").size() >= 24:
		return
	var shot: FRAGMENT = FRAGMENT.new()
	shot.effects = effects()
	shot.damage = 3.0
	shot.position = CONTACTS.damage_center(enemy)
	shot.direction = shot.position.direction_to(CONTACTS.damage_center(target))
	shot.excluded = [(enemy as CollisionObject2D).get_rid()]
	if enemy.get("stats") is Dictionary:
		shot.sheet = enemy.get("stats").shot as Texture2D
		shot.frames = int(enemy.get("stats").frames)
	add_child(shot)


func mutation_hit(enemy: Node2D, damage: float) -> void:
	if valid_enemy(enemy):
		effects().apply_hit(enemy, damage, Vector2.ZERO, 0.0)


func valid_enemy(enemy: Node2D) -> bool:
	return is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_in_group(&"controlled_monsters") and enemy.has_method("is_alive") and bool(enemy.call("is_alive"))


func is_boss(enemy: Node2D) -> bool:
	return enemy.has_method("can_receive_damage") or enemy.has_method("get_boss_health") or enemy.is_in_group(&"boss_bodies") or enemy.is_in_group(&"elemental_golem") or bool(enemy.get_meta(&"is_boss", false)) or enemy.get_script() == preload("res://scripts/enemies/asterion_body.gd")


func enemies() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = node as Node2D
		if valid_enemy(enemy):
			result.append(enemy)
	return result


func nearest_enemy(point: Vector2, radius: float, excluded: Node2D = null) -> Node2D:
	var result: Node2D
	var best: float = radius * radius
	for enemy: Node2D in enemies():
		if enemy == excluded:
			continue
		var distance: float = enemy.global_position.distance_squared_to(point)
		if distance < best:
			best = distance
			result = enemy
	return result


func has_floor(point: Vector2) -> bool:
	var world: Node = player.get_parent()
	return bool(world.call("is_ground_surface_point", point)) if world.has_method("is_ground_surface_point") else player.arena_bounds.has_point(point)


func height_at(point: Vector2) -> float:
	var world: Node = player.get_parent()
	return float(world.call("_terrain_and_warp_height", point)) if world.has_method("_terrain_and_warp_height") else 0.0


func companion_direction(from: Vector2, to: Vector2) -> Vector2:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, 1)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space.intersect_ray(query).is_empty() and has_floor(from.lerp(to, 0.5)) and has_floor(to):
		return from.direction_to(to)
	if _navigation == null or not _navigation_bounds.grow(-48.0).has_point(from) or not _navigation_bounds.has_point(to):
		_navigation = EnemyNavigationGrid.new()
		_navigation_bounds = Rect2(from, Vector2.ZERO).expand(to).grow(80.0)
		_navigation.build(get_world_2d(), _navigation_bounds, 4.0, 1)
		for y: int in range(_navigation.grid.region.size.y):
			for x: int in range(_navigation.grid.region.size.x):
				var cell: Vector2i = Vector2i(x, y)
				if not has_floor(_navigation.grid.get_point_position(cell)):
					_navigation.grid.set_point_solid(cell, true)
	var path: PackedVector2Array = _navigation.find_path(from, to)
	for waypoint: Vector2 in path:
		if from.distance_to(waypoint) > 5.0:
			return from.direction_to(waypoint)
	return Vector2.ZERO


func visual(kind: StringName, at: Vector2, lifetime: float, radius: float = 18.0) -> VISUAL:
	var node: VISUAL = VISUAL.new()
	node.kind = kind
	node.position = at
	node.lifetime = lifetime
	node.radius = radius
	add_child(node)
	return node


func _exit_tree() -> void:
	_release_hosts()
	if is_instance_valid(player):
		player.mutation_invisible = false
		if player.card_effects == self:
			player.card_effects = null
