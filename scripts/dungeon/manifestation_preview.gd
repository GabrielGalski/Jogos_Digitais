extends Node2D
## Local manifestation previews using the shared card runtime.
const BANSHEE_CHANNEL: Script = preload("res://scripts/dungeon/banshee_channel.gd")
const FLAMETHROWER: Script = preload("res://scripts/dungeon/efreeti_flamethrower.gd")

const PROJECTILE: PackedScene = preload("res://scenes/dungeon/manifestation_projectile.tscn")
const LASER_1: Texture2D = preload("res://assets/cards/manifestacao/olho_de_beholder M04/projectiles/projectile1.png")
const LASER_2: Texture2D = preload("res://assets/cards/manifestacao/olho_de_beholder M04/projectiles/projectile2.png")
const LASER_3: Texture2D = preload("res://assets/cards/manifestacao/olho_de_beholder M04/projectiles/projectile3.png")
const CODES: Array[StringName] = [&"M01", &"M02", &"M04", &"M05", &"M06", &"M03", &"M07", &"M08"]
const NAMES: Array[String] = ["Gotas de Slime", "Massa de Slime", "Olho de Beholder", "Brotos de Fungoide", "Cauda de Mantícora", "Grito de Banshee", "Coração de Efreeti", "Lança-chamas"]
const CARDS: Array[ManifestationCard] = [
	preload("res://resources/cards/preview/M01.tres"),
	preload("res://resources/cards/preview/M02.tres"),
	preload("res://resources/cards/preview/M04.tres"),
	preload("res://resources/cards/preview/M05.tres"),
	preload("res://resources/cards/preview/M06.tres"),
	preload("res://resources/cards/preview/M03.tres"),
	preload("res://resources/cards/preview/M07.tres"),
	preload("res://resources/cards/preview/M08.tres"),
]

@onready var player: Player = $"../Nox"
@onready var gun: Node2D = $"../Nox/BoosterShooter"
@onready var projectiles: Node2D = $"../ManifestationProjectiles"
@onready var target: Minotaur = get_node_or_null("../TrainingMinotaur") as Minotaur
@onready var beam: Line2D = $LaserBeam
@onready var reticle: Node2D = $"../CombatUI/Crosshair"
@onready var status: Label = $"../CombatUI/Status"
@onready var presentation: Node2D = get_node_or_null("../ProjectileWorldStyle") as Node2D

var selected_index: int = 0
var cooldown: float = 0.0
var laser_tick: float = 0.0
var visual_time: float = 0.0
var total_damage: float = 0.0
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var runtime: CardCombatRuntime
var combat_effects: CombatEffects
var laser_infusion_remaining: float = 0.0
var banshee: Node
var flame_stream: Node2D
var flame_tick: float = 0.0
var flame_infusion_remaining: float = 0.0


func _ready() -> void:
	random.randomize()
	gun.call(&"set_combat_enabled", false)
	gun.set(&"use_card_loadout", true)
	gun.set(&"effects", null)
	gun.set(&"projectiles", null)
	gun.set(&"projectile_presentation", presentation)
	runtime = gun.get(&"card_runtime") as CardCombatRuntime
	combat_effects = CombatEffects.new()
	combat_effects.name = "AspectEffects"
	combat_effects.camera_feedback_enabled = false
	combat_effects.explosion_visuals_enabled = false
	add_child(combat_effects)
	# Companion and beam are positioned by the presentation loop, not interpolated twice.
	var companion: Node = gun.get("companion") as Node
	if is_instance_valid(companion):
		companion.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	beam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	beam.z_as_relative = false
	beam.z_index = 1
	_equip_selected()
	banshee = BANSHEE_CHANNEL.new()
	banshee.name = "BansheeChannel"
	add_child(banshee)
	banshee.call(&"setup", player, gun.get_node("WeaponPivot/Muzzle"), runtime, combat_effects, $"../CombatUI", _cursor_world_position)
	beam.visible = false
	if is_instance_valid(target):
		target.damaged.connect(_on_target_damaged)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode != KEY_SPACE and key.keycode != KEY_SPACE:
		return
	selected_index = (selected_index + 1) % CODES.size()
	banshee.call(&"tick", 0.0, false, CODES[selected_index] == &"M03")
	if CODES[selected_index] != &"M08":
		_stop_flamethrower()
	_equip_selected()
	cooldown = 0.0
	laser_tick = 0.0
	beam.visible = false
	_update_hud()
	get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	gun.set(&"aim_screen_override", reticle.position)
	visual_time += delta
	laser_infusion_remaining = maxf(0.0, laser_infusion_remaining - delta)
	flame_infusion_remaining = maxf(0.0, flame_infusion_remaining - delta)
	cooldown = maxf(0.0, cooldown - delta)
	var banshee_selected: bool = CODES[selected_index] == &"M03"
	var banshee_requested: bool = banshee_selected and not player.intro_locked and not player.dead and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	banshee.call(&"tick", delta, banshee_requested, banshee_selected)
	if player.intro_locked or player.dead:
		beam.visible = false
		_stop_flamethrower()
		return
	if CODES[selected_index] == &"M08":
		beam.visible = false
		_update_flamethrower(delta)
		return
	_stop_flamethrower()
	if CODES[selected_index] == &"M04":
		_update_laser(delta)
		return
	beam.visible = false
	if banshee_selected:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cooldown <= 0.0:
		_fire()


func _fire() -> void:
	var code: StringName = CODES[selected_index]
	if code == &"M03" or code == &"M08":
		return
	if code == &"M05" and _active_mushrooms() >= 3:
		cooldown = 0.1
		return
	var muzzle: Marker2D = gun.get_node("WeaponPivot/Muzzle") as Marker2D
	var aim: Vector2 = (_cursor_world_position() - muzzle.global_position).normalized()
	if aim.is_zero_approx():
		aim = Vector2.RIGHT
	if code == &"M06":
		aim = aim.rotated(random.randf_range(-0.42, 0.42))
	var attack: CardAttack = runtime.create_attack()
	if attack == null:
		return
	var projectile: Node2D = PROJECTILE.instantiate() as Node2D
	projectiles.add_child(projectile)
	projectile.global_position = muzzle.global_position + aim * (5.0 if code != &"M05" else 0.0)
	projectile.call(&"configure", code, aim, attack, combat_effects, player)
	gun.call(&"present_shot", projectile, code)
	projectile.reset_physics_interpolation()
	cooldown = attack.fire_interval


func _update_flamethrower(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_stop_flamethrower()
		return
	if not is_instance_valid(flame_stream) or flame_stream.is_queued_for_deletion():
		var initial_attack: CardAttack = runtime.create_attack()
		if initial_attack == null:
			return
		flame_stream = FLAMETHROWER.new() as Node2D
		projectiles.add_child(flame_stream)
		var muzzle: Marker2D = gun.get_node("WeaponPivot/Muzzle") as Marker2D
		flame_stream.call(&"setup", muzzle, _cursor_world_position, initial_attack)
		if is_instance_valid(presentation):
			presentation.call(&"style_channel", flame_stream)
	else:
		flame_stream.call(&"start_firing")
	flame_stream.call(&"follow_source")
	flame_tick -= delta
	if flame_tick > 0.0:
		return
	var attack: CardAttack = runtime.create_attack()
	if attack == null:
		return
	var infusion_available: bool = attack.explosion_damage > 0.0 and flame_infusion_remaining <= 0.0
	if not infusion_available:
		attack.explosion_damage = 0.0
	var hit_enemy: bool = bool(flame_stream.call(&"apply_channel_hit", attack, combat_effects))
	if hit_enemy and infusion_available:
		flame_infusion_remaining = 0.30
	flame_tick += attack.fire_interval


func _stop_flamethrower() -> void:
	if is_instance_valid(flame_stream):
		flame_stream.call(&"stop_firing")
	flame_tick = 0.0


func _equip_selected() -> void:
	var base: CardLoadout = gun.get("initial_loadout") as CardLoadout
	var loadout: CardLoadout = base.duplicate(true) as CardLoadout if base != null else CardLoadout.new()
	loadout.manifestation = CARDS[selected_index]
	gun.call(&"equip_cards", loadout)


func _active_mushrooms() -> int:
	var count: int = 0
	for child: Node in projectiles.get_children():
		if child.get(&"mode") == &"M05" and not child.is_queued_for_deletion():
			count += 1
	return count


func _update_laser(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		beam.visible = false
		laser_tick = 0.0
		return
	var muzzle: Marker2D = gun.get_node("WeaponPivot/Muzzle") as Marker2D
	var origin: Vector2 = muzzle.global_position
	var direction: Vector2 = (_cursor_world_position() - origin).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var endpoint: Vector2 = origin + direction * 240.0
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, endpoint, 4)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	var enemy: Node2D = null
	if not hit.is_empty():
		endpoint = hit.get("position") as Vector2
		enemy = hit.get("collider") as Node2D
	beam.points = PackedVector2Array([to_local(origin), to_local(endpoint)])
	var frame: int = int(visual_time * 12.0) % 3
	beam.texture = LASER_1 if frame == 0 else LASER_2 if frame == 1 else LASER_3
	beam.visible = true
	laser_tick -= delta
	if not _valid_enemy(enemy):
		# Missing a target must not bank damage ticks for the next enemy.
		laser_tick = 0.0
		return
	while laser_tick <= 0.0:
		var attack: CardAttack = runtime.create_attack()
		if attack == null:
			break
		# The infusion has its own clock; releasing or changing targets cannot reset it.
		if laser_infusion_remaining > 0.0:
			attack.explosion_damage = 0.0
		elif attack.explosion_damage > 0.0:
			laser_infusion_remaining = 0.5
		attack.apply_primary_hit(enemy, endpoint, direction, combat_effects)
		laser_tick += attack.fire_interval
		if not _valid_enemy(enemy):
			break


func _valid_enemy(enemy: Node2D) -> bool:
	return is_instance_valid(enemy) and enemy.is_in_group(&"enemy_bodies") and enemy.has_method(&"is_alive") and bool(enemy.call(&"is_alive"))


func _cursor_world_position() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * reticle.position


func _on_target_damaged(amount: float, _remaining: float) -> void:
	total_damage += amount
	_update_hud()


func _update_hud() -> void:
	var code: StringName = CODES[selected_index]
	status.text = "%s  %s   |   Espaço: trocar   Shift: dash   |   Dano: %d" % [code, NAMES[selected_index], roundi(total_damage)]
	var color: Color = Color("#a8e387")
	match code:
		&"M02":
			color = Color("#67c974")
		&"M03":
			color = Color("#b9f4ee")
		&"M04":
			color = Color("#ffe26b")
		&"M05":
			color = Color("#c5a7ff")
		&"M06":
			color = Color("#f3a5c2")
		&"M07":
			color = Color("#fa6a0a")
		&"M08":
			color = Color("#ffd541")
	reticle.call(&"set_tint", color)
