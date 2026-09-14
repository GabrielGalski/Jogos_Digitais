extends Node2D
## The MVP weapon rig, now unlocked by the tutorial reveal.
signal shot_fired
const BULLET: PackedScene = preload("res://scenes/combat/projectiles/rapid_electric_bullet.tscn")
const WEAPON_SCALE: float = 0.55
const FORWARD_DISTANCE: float = 10.5
const RECOIL_DISTANCE: float = 4.5
@export var fire_interval: float = 0.09
@export var cutscene_pose_turn_speed: float = 7.5
var equipped: bool = false
var combat_enabled: bool = false
var aim_direction: Vector2 = Vector2.UP
var float_time: float = 0.0
var shot_recoil: float = 0.0
var cooldown: float = 0.0
var require_mouse_release: bool = true
var cutscene_pose_active: bool = false
var effects: CombatEffects
var projectiles: Node2D
@onready var player: Player = get_parent() as Player
@onready var pivot: Node2D = $WeaponPivot
@onready var weapon: Sprite2D = $WeaponPivot/Weapon
@onready var muzzle: Marker2D = $WeaponPivot/Muzzle

func _ready() -> void:
	hide()

func reveal() -> void:
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
	var bullet: RapidElectricBullet = BULLET.instantiate() as RapidElectricBullet
	projectiles.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.setup(aim_direction, effects)
	bullet.reset_physics_interpolation()
	cooldown = fire_interval
	shot_recoil = 0.85
	shot_fired.emit()
	return bullet

func _update_rig(delta: float) -> void:
	var mouse_world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
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
	var weapon_aim: Vector2 = aim_direction if cutscene_pose_active else mouse_world - pivot.global_position
	pivot.rotation = weapon_aim.angle()
	pivot.rotation += -0.065 * 0.85 * pulse * (-1.0 if aim_direction.x < 0.0 else 1.0)
	weapon.flip_v = aim_direction.x < 0.0
	player.body.flip_h = aim_direction.x < 0.0


