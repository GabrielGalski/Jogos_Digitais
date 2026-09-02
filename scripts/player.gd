extends CharacterBody2D
class_name Player

signal contact_damage_received(amount: int)

const WEAPON_SCALE := 0.55
const WEAPON_GRIP_PIXEL := Vector2(7.0, 4.0)
const WEAPON_FORWARD_DISTANCE := 10.5
const WEAPON_FLOAT_SPEED := 1.8
const WEAPON_FLOAT_AMOUNT := Vector2(0.3, 0.65)
const WEAPON_RECOIL_DISTANCE := 4.5
const WEAPON_RECOIL_ATTACK_DURATION := 0.035
const WEAPON_RECOIL_HOLD_DURATION := 0.10
const WEAPON_RECOIL_RECOVERY_DURATION := 0.14
const CONTACT_DAMAGE_FLASH_DURATION := 0.13

@export var movement_speed := 82.0

@onready var body: AnimatedSprite2D = $Body
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon: Sprite2D = $WeaponPivot/Weapon
@onready var damage_material: ShaderMaterial = body.material as ShaderMaterial

var movement_bounds := Rect2(-Vector2(372, 204), Vector2(744, 408))
var last_aim_direction := Vector2.RIGHT
var weapon_float_time := 0.0
var weapon_recoil_strength := 0.0
var weapon_recoil_hold_time := 0.0
var contact_damage_tween: Tween


func _ready() -> void:
	weapon.position = -WEAPON_GRIP_PIXEL * WEAPON_SCALE
	weapon.scale = Vector2.ONE * WEAPON_SCALE
	weapon_pivot.position = Vector2.RIGHT * WEAPON_FORWARD_DISTANCE


func _physics_process(_delta: float) -> void:
	var input_direction := _get_movement_input()
	velocity = input_direction * movement_speed
	move_and_slide()
	global_position = global_position.clamp(movement_bounds.position, movement_bounds.end)

	_update_animation(input_direction)


func _process(delta: float) -> void:
	# Atualizada em todo frame visual para acompanhar o mouse sem atrasos.
	_update_floating_weapon(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Renova a pressao sem zerar o recuo entre cliques consecutivos.
			weapon_recoil_hold_time = WEAPON_RECOIL_HOLD_DURATION


func set_movement_bounds(bounds: Rect2) -> void:
	movement_bounds = bounds


func receive_contact_damage(amount: int) -> void:
	# Gancho de gameplay para o futuro sistema de vida, ainda nao definido no MVP.
	contact_damage_received.emit(amount)
	if contact_damage_tween and contact_damage_tween.is_valid():
		contact_damage_tween.kill()
	damage_material.set_shader_parameter(&"flash_amount", 1.0)
	contact_damage_tween = create_tween()
	contact_damage_tween.tween_method(
		_set_contact_damage_flash,
		1.0,
		0.0,
		CONTACT_DAMAGE_FLASH_DURATION
	)


func _set_contact_damage_flash(value: float) -> void:
	damage_material.set_shader_parameter(&"flash_amount", value)


func _update_animation(input_direction: Vector2) -> void:
	var next_animation: StringName = &"run" if not input_direction.is_zero_approx() else &"idle"
	if body.animation != next_animation:
		body.play(next_animation)


func _get_movement_input() -> Vector2:
	# Polling fisico continuo evita perder teclas em diagonais ou mudancas rapidas.
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	return direction.normalized()


func _update_floating_weapon(delta: float) -> void:
	# Converte a posicao real do cursor para o mundo, inclusive nos cantos da viewport.
	var mouse_world_position := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var character_aim_vector := mouse_world_position - global_position
	if character_aim_vector.length_squared() >= 0.001:
		last_aim_direction = character_aim_vector.normalized()

	weapon_float_time += delta * WEAPON_FLOAT_SPEED
	var float_offset := Vector2(
		sin(weapon_float_time * 0.65) * WEAPON_FLOAT_AMOUNT.x,
		sin(weapon_float_time) * WEAPON_FLOAT_AMOUNT.y
	)
	var recoil_strength := _update_weapon_recoil(delta)
	var recoil_offset := -last_aim_direction * WEAPON_RECOIL_DISTANCE * recoil_strength
	# A empunhadura fica fora do eixo do corpo e orbita sempre no lado do cursor.
	weapon_pivot.position = (
		last_aim_direction * WEAPON_FORWARD_DISTANCE
		+ recoil_offset
		+ float_offset
	)
	# A camada 0 do Player fica acima da arena, mas abaixo do Body (camada 1).
	# Assim apenas a parte sobreposta e ocultada, sem fazer a arma sumir no chao.
	weapon_pivot.z_index = 0 if recoil_strength > 0.12 else 2

	var weapon_aim_vector := mouse_world_position - weapon_pivot.global_position
	if weapon_aim_vector.length_squared() < 0.001:
		weapon_aim_vector = last_aim_direction
	weapon_pivot.rotation = weapon_aim_vector.angle()

	var aiming_left := last_aim_direction.x < 0.0
	weapon.flip_v = aiming_left
	body.flip_h = aiming_left


func _update_weapon_recoil(delta: float) -> float:
	# Manter o botao pressionado ou clicar repetidamente segura a arma recuada.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		weapon_recoil_hold_time = WEAPON_RECOIL_HOLD_DURATION

	if weapon_recoil_hold_time > 0.0:
		weapon_recoil_hold_time = maxf(weapon_recoil_hold_time - delta, 0.0)
		weapon_recoil_strength = move_toward(
			weapon_recoil_strength,
			1.0,
			delta / WEAPON_RECOIL_ATTACK_DURATION
		)
	else:
		weapon_recoil_strength = move_toward(
			weapon_recoil_strength,
			0.0,
			delta / WEAPON_RECOIL_RECOVERY_DURATION
		)

	return weapon_recoil_strength
