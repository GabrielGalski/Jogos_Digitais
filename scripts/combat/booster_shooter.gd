extends Node2D
## Caster presentation and input; authored cards drive the initial combat loadout.
signal shot_fired
const BULLET: PackedScene = preload("res://scenes/combat/projectiles/rapid_electric_bullet.tscn")
const M01_PROJECTILE: PackedScene = preload("res://scenes/dungeon/manifestation_projectile.tscn")
const COMPANION: Script = preload("res://scripts/combat/deck_box_companion.gd")
@export var use_deck_box: bool = true
@export var use_card_loadout: bool = true
@export var use_m01_projectile: bool = false
@export var initial_loadout: CardLoadout = preload("res://resources/cards/starter_loadout.tres")
var card_runtime: CardCombatRuntime = CardCombatRuntime.new()
@export_flags_2d_physics var projectile_obstacle_mask: int = 0
var companion: Node2D
const WEAPON_SCALE: float = 0.55
const FORWARD_DISTANCE: float = 10.5
const RECOIL_DISTANCE: float = 4.5
@export var fire_interval: float = 0.18
@export var cutscene_pose_turn_speed: float = 7.5
var equipped: bool = false
var combat_enabled: bool = false
var aim_direction: Vector2 = Vector2.UP
var float_time: float = 0.0
var shot_recoil: float = 0.0
var cooldown: float = 0.0
var require_mouse_release: bool = true
var cutscene_pose_active: bool = false
var aim_screen_override: Vector2 = Vector2.INF
var effects: CombatEffects
var projectiles: Node2D
var projectile_presentation: Node2D
@onready var player: Player = get_parent() as Player
@onready var pivot: Node2D = $WeaponPivot
@onready var weapon: Sprite2D = $WeaponPivot/Weapon
@onready var muzzle: Marker2D = $WeaponPivot/Muzzle

func _ready() -> void:
	if not equip_cards(initial_loadout):
		push_error("BoosterShooter received an invalid initial card loadout.")
	player.defeated.connect(_reset_card_effects)
	if use_deck_box:
		equipped = true
		show()
		companion = COMPANION.new() as Node2D
		companion.name = "DeckBox"
		add_child(companion)
		companion.call("configure", self)
		weapon.hide()
		_update_rig(0.0)
	else:
		hide()

func reveal() -> void:
	if use_deck_box and equipped:
		return
	equipped = true
	show()
	aim_direction = Vector2.RIGHT
	set_cutscene_pose(false)

func set_cutscene_pose(enabled: bool) -> void:
	cutscene_pose_active = enabled
	if enabled:
		shot_recoil = 0.0
	_update_rig(0.0)

func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	require_mouse_release = true
	cooldown = 0.0

func _process(delta: float) -> void:
	card_runtime.tick(delta)
	player.card_movement_multiplier = card_runtime.movement_multiplier() if use_card_loadout else 1.0
	if not equipped:
		return
	_update_rig(delta)
	cooldown = maxf(cooldown - delta, 0.0)
	if not combat_enabled or player.intro_locked:
		require_mouse_release = true
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		require_mouse_release = false
	elif not require_mouse_release:
		fire_once()

func fire_once() -> Node2D:
	if not equipped or not combat_enabled or player.intro_locked or cooldown > 0.0:
		return null
	if not is_instance_valid(effects) or not is_instance_valid(projectiles):
		return null
	var attack: CardAttack
	if use_card_loadout:
		attack = card_runtime.create_attack()
		if attack == null:
			return null
	if use_m01_projectile:
		if attack == null:
			return null
		var slime: Node2D = M01_PROJECTILE.instantiate() as Node2D
		projectiles.add_child(slime)
		slime.global_position = muzzle.global_position + aim_direction * 5.0
		slime.add_to_group(&"player_projectiles")
		slime.call(&"configure", &"M01", aim_direction, attack, effects, player)
		present_shot(slime, &"M01")
		slime.reset_physics_interpolation()
		cooldown = attack.fire_interval
		shot_fired.emit()
		return slime
	var bullet: RapidElectricBullet = BULLET.instantiate() as RapidElectricBullet
	if attack != null:
		bullet.card_attack = attack
		bullet.direct_damage = attack.damage
		bullet.movement_speed = attack.projectile_speed
		bullet.maximum_lifetime = attack.projectile_lifetime
		bullet.explosion_damage = attack.explosion_damage
		bullet.explosion_radius = attack.explosion_radius
	projectiles.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.setup(aim_direction, effects)
	bullet.obstacle_mask = projectile_obstacle_mask
	bullet.collision_mask |= projectile_obstacle_mask
	bullet.reset_physics_interpolation()
	cooldown = attack.fire_interval if attack != null else fire_interval
	shot_recoil = 0.85
	shot_fired.emit()
	return bullet


func present_shot(projectile: Node2D, code: StringName) -> void:
	shot_recoil = 0.85
	if not is_instance_valid(projectile_presentation):
		return
	var visual_profile: Resource = projectile_presentation.get("profile") as Resource
	shot_recoil = float(visual_profile.get("shot_recoil"))
	projectile_presentation.call(&"style_projectile", projectile, code)
	projectile_presentation.call(&"flash_shot", muzzle, code)


func equip_cards(loadout: CardLoadout) -> bool:
	if not card_runtime.equip(loadout):
		return false
	if is_instance_valid(player):
		player.card_movement_multiplier = 1.0
	return true


func _reset_card_effects() -> void:
	card_runtime.reset_effects()
	player.card_movement_multiplier = 1.0

func _update_rig(delta: float) -> void:
	if use_deck_box and is_instance_valid(companion):
		companion.call("update_pose", delta)
		return
	var mouse_world: Vector2 = get_aim_world_position()
	if cutscene_pose_active:
		var turn: float = wrapf(Vector2.RIGHT.angle() - aim_direction.angle(), -PI, PI)
		var turn_step: float = clampf(turn, -cutscene_pose_turn_speed * delta, cutscene_pose_turn_speed * delta)
		aim_direction = aim_direction.rotated(turn_step).normalized()
	else:
		var to_mouse: Vector2 = mouse_world - player.global_position
		if to_mouse.length_squared() > 0.001:
			aim_direction = to_mouse.normalized()
	float_time += delta * 1.8
	var float_offset: Vector2 = Vector2(sin(float_time * 0.65) * 0.3, sin(float_time) * 0.65)
	var pulse: float = shot_recoil
	shot_recoil = move_toward(shot_recoil, 0.0, delta / 0.075)
	weapon.scale = Vector2(1.0 - pulse * 0.09, 1.0 + pulse * 0.07) * WEAPON_SCALE
	pivot.position = aim_direction * (FORWARD_DISTANCE - RECOIL_DISTANCE * pulse) + float_offset
	pivot.z_index = -1 if pulse > 0.12 else 2
	# Rotation follows the resolved aim from Nox, never the mouse-to-pivot vector.
	# Near Nox's center that latter vector points backward and visually flips the weapon.
	pivot.rotation = aim_direction.angle()
	pivot.rotation += -0.065 * 0.85 * pulse * (-1.0 if aim_direction.x < 0.0 else 1.0)
	weapon.flip_v = aim_direction.x < 0.0
	player.body.flip_h = aim_direction.x < 0.0


func get_aim_world_position() -> Vector2:
	var cursor: Vector2 = aim_screen_override if aim_screen_override.is_finite() else get_viewport().get_mouse_position()
	return get_viewport().get_canvas_transform().affine_inverse() * cursor
