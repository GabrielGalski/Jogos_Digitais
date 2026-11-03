extends Node2D
## Caster presentation and input; authored cards drive the initial combat loadout.
signal shot_fired
const BULLET: PackedScene = preload("res://scenes/combat/projectiles/rapid_electric_bullet.tscn")
const M01_PROJECTILE: PackedScene = preload("res://scenes/dungeon/manifestation_projectile.tscn")
const COMPANION: Script = preload("res://scripts/combat/deck_box_companion.gd")
@export var use_deck_box: bool = false
@export var use_card_loadout: bool = true
@export var use_m01_projectile: bool = false
@export var initial_loadout: CardLoadout = preload("res://resources/cards/starter_loadout.tres")
var card_runtime: CardCombatRuntime = CardCombatRuntime.new()
var manifestation_driver: Node = null
@export_flags_2d_physics var projectile_obstacle_mask: int = 0
var companion: Node2D
const WEAPON_SCALE: float = 0.495
const FORWARD_DISTANCE: float = 10.5
const RECOIL_DISTANCE: float = 4.5
const GUN_ANCHOR: Vector2 = Vector2(26, 31)
const GUN_MUZZLE: Vector2 = Vector2(45, 31)
const GUN_TEXTURE: Texture2D = preload("res://assets/characters/player/gun/booster_shooter.png")
const OUTER_GLOW: Script = preload("res://scripts/visual/sprite_outer_glow.gd")
const SHOT_EFFECTS: Array[Texture2D] = [
	preload("res://assets/characters/player/gun/shoot_effect1.png"),
	preload("res://assets/characters/player/gun/shoot_effect2.png"),
	preload("res://assets/characters/player/gun/shoot_effect3.png"),
	preload("res://assets/characters/player/gun/shoot_effect4.png"),
	preload("res://assets/characters/player/gun/shoot_effect5.png"),
]
const EFFECT_DURATION: float = 0.125
@export_range(15.0, 90.0, 1.0) var maximum_aim_tilt: float = 90.0
var aim_allowed: bool = true
var _aim_side: float = 1.0
var _effect_remaining: float = 0.0
var _effect: Sprite2D = null
var _effect_glow: Sprite2D = null
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
		equipped = true
		show()
		weapon.texture = GUN_TEXTURE
		weapon.centered = false
		weapon.show()
		_create_gun_effects()
		_update_rig(0.0)

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
	if is_instance_valid(manifestation_driver):
		var allowed: bool = combat_enabled and not player.dead and not player.intro_locked and not player.is_parry_feedback_active() and is_aim_allowed()
		if not allowed:
			require_mouse_release = true
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			require_mouse_release = false
		manifestation_driver.call("set_trigger", allowed and not require_mouse_release and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
		return
	if not combat_enabled or player.intro_locked or player.is_parry_feedback_active():
		require_mouse_release = true
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		require_mouse_release = false
	elif not require_mouse_release:
		fire_once()

func fire_once() -> Node2D:
	if not equipped or not combat_enabled or player.intro_locked or player.is_parry_feedback_active() or cooldown > 0.0:
		return null
	if not is_instance_valid(effects) or not is_instance_valid(projectiles):
		return null
	if not is_aim_allowed():
		return null
	# Aim, muzzle and the aligned sprite canvas must belong to this same shot.
	_update_rig(0.0)
	if is_instance_valid(manifestation_driver):
		return manifestation_driver.call("fire_once") as Node2D
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
	trigger_muzzle_effect(&"M01" if use_card_loadout else &"")
	shot_fired.emit()
	return bullet


func set_manifestation_driver(driver: Node) -> void:
	manifestation_driver = driver
	_effect_remaining = 0.0
	if _effect != null:
		_effect.hide()
		_effect_glow.hide()


func present_procedural_shot() -> void:
	shot_recoil = 0.85
	shot_fired.emit()


func present_shot(projectile: Node2D, code: StringName) -> void:
	shot_recoil = 0.85
	trigger_muzzle_effect(code)
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
	if cutscene_pose_active:
		var turn: float = wrapf(Vector2.RIGHT.angle() - aim_direction.angle(), -PI, PI)
		var turn_step: float = clampf(turn, -cutscene_pose_turn_speed * delta, cutscene_pose_turn_speed * delta)
		aim_direction = aim_direction.rotated(turn_step).normalized()
	else:
		_resolve_aim()
	float_time += delta * 1.8
	var float_offset: Vector2 = Vector2(sin(float_time * 0.65) * 0.3, sin(float_time) * 0.65)
	var pulse: float = shot_recoil
	shot_recoil = move_toward(shot_recoil, 0.0, delta / 0.08)
	weapon.scale = Vector2(1.0 - pulse * 0.09, 1.0 + pulse * 0.07) * WEAPON_SCALE
	pivot.position = aim_direction * (FORWARD_DISTANCE - RECOIL_DISTANCE * pulse) + float_offset
	pivot.z_index = 0 if pulse > 0.12 or aim_direction.y < -0.75 else 2
	# Rotation follows the resolved aim from Nox, never the mouse-to-pivot vector.
	# Near Nox's center that latter vector points backward and visually flips the weapon.
	pivot.rotation = aim_direction.angle()
	pivot.rotation += -0.065 * 0.85 * pulse * _aim_side
	weapon.flip_v = _aim_side < 0.0
	var anchor: Vector2 = GUN_ANCHOR
	var mouth: Vector2 = GUN_MUZZLE
	if weapon.flip_v:
		anchor.y = GUN_TEXTURE.get_height() - anchor.y
		mouth.y = GUN_TEXTURE.get_height() - mouth.y
	weapon.position = -anchor * weapon.scale
	muzzle.position = (mouth - anchor) * weapon.scale
	_update_gun_effects(delta)
	if is_instance_valid(player.body) and player.velocity.is_zero_approx() and not player.intro_locked:
		player.body.face_direction(aim_direction)


func is_aim_allowed() -> bool:
	_resolve_aim()
	return aim_allowed


func _resolve_aim() -> void:
	if not is_instance_valid(player):
		return
	var requested: Vector2 = get_aim_world_position() - player.surface_world_position()
	if requested.length_squared() < 0.001:
		return
	var direction: Vector2 = requested.normalized()
	var angle_limit: float = deg_to_rad(maximum_aim_tilt)
	# Preserve sprite handedness near vertical aim, without clamping the real shot.
	if absf(requested.x) > 3.0:
		_aim_side = signf(direction.x)
	if maximum_aim_tilt >= 90.0:
		aim_allowed = true
		aim_direction = direction
		return
	# The old cone remains an optional inspector setting, not the active default.
	aim_allowed = absf(direction.x) >= cos(angle_limit)
	var tilt: float = atan2(direction.y, absf(direction.x))
	tilt = clampf(tilt, -angle_limit, angle_limit)
	aim_direction = Vector2(cos(tilt) * _aim_side, sin(tilt))


func trigger_muzzle_effect(code: StringName) -> void:
	if use_deck_box or _effect == null:
		return
	_effect_remaining = EFFECT_DURATION
	shot_recoil = maxf(shot_recoil, 0.85)
	_effect.modulate = Color("#00baa7") if code == &"M01" else Color.WHITE
	_effect_glow.modulate = Color(_effect.modulate, 0.6)
	_update_gun_effects(0.0)


func _create_gun_effects() -> void:
	var opaque: CanvasItemMaterial = CanvasItemMaterial.new()
	opaque.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_effect = Sprite2D.new()
	_effect.name = "ShotEffect"
	_effect.centered = false
	_effect.material = opaque
	_effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_effect.z_index = 1
	pivot.add_child(_effect)
	var additive: CanvasItemMaterial = opaque.duplicate() as CanvasItemMaterial
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_effect_glow = Sprite2D.new()
	_effect_glow.name = "ShotGlow"
	_effect_glow.centered = false
	_effect_glow.material = additive
	_effect_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pivot.add_child(_effect_glow)
	_effect.hide()
	_effect_glow.hide()


func _update_gun_effects(delta: float) -> void:
	if _effect == null:
		return
	_effect_remaining = maxf(0.0, _effect_remaining - delta)
	_effect.visible = _effect_remaining > 0.0
	_effect_glow.visible = _effect.visible
	if not _effect.visible:
		return
	var age: float = EFFECT_DURATION - _effect_remaining
	var frame: int = mini(int(age / EFFECT_DURATION * SHOT_EFFECTS.size()), SHOT_EFFECTS.size() - 1)
	_effect.texture = SHOT_EFFECTS[frame]
	_effect.position = weapon.position
	_effect.scale = weapon.scale
	_effect.flip_v = weapon.flip_v
	_effect_glow.texture = OUTER_GLOW.texture_for(_effect.texture)
	_effect_glow.position = weapon.position - Vector2.ONE * OUTER_GLOW.PADDING * weapon.scale
	_effect_glow.scale = weapon.scale
	_effect_glow.flip_v = weapon.flip_v
	_effect_glow.modulate.a = 0.6 * _effect_remaining / EFFECT_DURATION


func get_aim_world_position() -> Vector2:
	var cursor: Vector2 = aim_screen_override if aim_screen_override.is_finite() else get_viewport().get_mouse_position()
	return get_viewport().get_canvas_transform().affine_inverse() * cursor
