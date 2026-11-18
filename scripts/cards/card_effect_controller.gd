extends Node2D
## Scene-local card execution. Snapshots retain damage ownership across equipment changes.
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const VISUAL: Script = preload("res://scripts/cards/card_effect_visual.gd")
const FRAGMENT: Script = preload("res://scripts/cards/card_fragment.gd")
const SNAKE: Script = preload("res://scripts/cards/medusa_snake.gd")
const CONTROL: Script = preload("res://scripts/cards/temporary_enemy_control.gd")
var player: Player
var gun: Node2D
var runtime: CardCombatRuntime
var poisons: Dictionary = {}
var blasts: Array[Dictionary] = []
var mouths: Array[Dictionary] = []
var clouds: Array[Dictionary] = []
var invisible_remaining: float = 0.0
var decoy: Node2D
var _hosted: Node2D
var _previous_feet: Vector2
var _trail_distance: float = 0.0
var _area_tick: float = 0.0
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
	_previous_feet = player.global_position
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
		clouds.clear()
		for node: Node in get_children():
			if node is SNAKE:
				node.queue_free()
	if _was_invisible and not player.mutation_invisible:
		player.body.self_modulate.a = _body_alpha
		gun.visible = _gun_visible
		_was_invisible = false
	if player.dead or player.intro_locked or not bool(gun.get("combat_enabled")):
		_previous_feet = player.global_position
		_status.hide()
		return
	_tick_poison(delta)
	_drain_blasts()
	_tick_mouths(delta)
	_tick_clouds(delta)
	var kind: int = runtime.mutation_effect()
	if kind == 2 and float(runtime.cooldowns.get(&"U03", 0.0)) <= 0.0:
		runtime.cooldowns[&"U03"] = 2.0
		var target: Node2D = nearest_enemy(player.global_position, 180.0)
		if target != null:
			var ground: Vector2 = target.global_position
			if has_floor(ground):
				var at: Vector2 = ground - Vector2(0, height_at(ground))
				visual(&"warning", at, 0.25, 28.0)
				mouths.append({"at": at, "remaining": 0.25})
	var travel: float = player.global_position.distance_to(_previous_feet)
	if kind == 4 and travel < 48.0 and has_floor(player.global_position):
		_trail_distance += travel
		if _trail_distance >= 12.0:
			_trail_distance = fmod(_trail_distance, 12.0)
			_leave_cloud()
	else:
		_trail_distance = 0.0
	_previous_feet = player.global_position
	_status.visible = kind in [3, 5]
	_status.position = Vector2(10, get_viewport_rect().size.y - 17.0)
	if _status.visible:
		var left: float = float(runtime.cooldowns.get(&"U04" if kind == 3 else &"U06", 0.0))
		_status.text = ("F  Mandragora" if kind == 3 else "F  Doppelganger") + ("  %.1fs" % left if left > 0.0 else "  Pronto")


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_F or key.physical_keycode == KEY_F):
		if activate_mutation():
			get_viewport().set_input_as_handled()


func activate_mutation() -> bool:
	_bind_runtime()
	if get_tree().paused or player.dead or player.intro_locked or not bool(gun.get("combat_enabled")):
		return false
	var kind: int = runtime.mutation_effect()
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


func weapon_kill(attack: CardAttack, at: Vector2, ground: Vector2, damage: float, depth: int) -> void:
	if player.dead:
		return
	match attack.infusion_effect:
		0:
			blasts.append({"attack": attack, "at": at, "ground": ground, "depth": depth})
		1:
			for index: int in range(6):
				if get_tree().get_nodes_in_group(&"card_fragments").size() >= 24:
					break
				var fragment: FRAGMENT = FRAGMENT.new()
				fragment.attack = attack
				fragment.effects = effects()
				fragment.damage = damage * 0.15
				fragment.direction = Vector2.from_angle(TAU * float(index) / 6.0)
				fragment.position = at
				add_child(fragment)
		2:
			if attack.infusion_generation == runtime.infusion_generation:
				player.heal_fraction(0.03)


func _drain_blasts() -> void:
	var processed: int = 0
	while not blasts.is_empty() and processed < 64:
		processed += 1
		var blast: Dictionary = blasts.pop_front()
		var attack: CardAttack = blast.attack as CardAttack
		var depth: int = int(blast.depth)
		var damage: float = 18.0 if depth == 0 else 9.0 if depth == 1 else 3.0
		visual(&"blast", blast.at as Vector2, 0.22, 18.0)
		for enemy: Node2D in enemies():
			var at: Vector2 = CONTACTS.damage_center(enemy)
			if at.distance_to(blast.at as Vector2) <= 18.0:
				attack.apply_secondary_hit(enemy, damage, (blast.at as Vector2).direction_to(at), effects(), depth + 1)


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
			visual(&"mouth", at, 0.4, 28.0)
			for enemy: Node2D in enemies():
				if CONTACTS.damage_center(enemy).distance_to(at) <= 28.0:
					mutation_hit(enemy, 6.0)
			mouths.remove_at(index)


func _leave_cloud() -> void:
	if clouds.size() >= 24:
		return
	var ground: Vector2 = player.global_position
	var at: Vector2 = ground - Vector2(0, height_at(ground))
	visual(&"smoke", at, 3.0)
	clouds.append({"ground": ground, "remaining": 3.0})


func _tick_clouds(delta: float) -> void:
	for index: int in range(clouds.size() - 1, -1, -1):
		clouds[index].remaining = float(clouds[index].remaining) - delta
		if float(clouds[index].remaining) <= 0.0:
			clouds.remove_at(index)
	_area_tick -= delta
	if _area_tick > 0.0:
		return
	_area_tick = 0.25
	for enemy: Node2D in enemies():
		for cloud: Dictionary in clouds:
			var at: Vector2 = cloud.ground as Vector2
			if enemy.global_position.distance_to(at) <= 17.0 and absf(height_at(enemy.global_position) - height_at(at)) < 8.0:
				poison(enemy, 1.5, 2.0)
				break


func attach_slaad(enemy: Node2D) -> void:
	if not valid_enemy(enemy) or is_boss(enemy) or not enemy is CharacterBody2D or enemy.has_meta(&"card_control"):
		return
	if is_instance_valid(_hosted):
		_hosted.free()
	var control: CONTROL = CONTROL.new()
	control.service = self
	enemy.add_child(control)
	_hosted = control


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
	return is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.has_method("is_alive") and bool(enemy.call("is_alive"))


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
		if enemy == excluded or enemy.is_in_group(&"controlled_monsters"):
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
	if is_instance_valid(_hosted):
		_hosted.queue_free()
	if is_instance_valid(player):
		player.mutation_invisible = false
		if player.card_effects == self:
			player.card_effects = null
