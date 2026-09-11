extends CharacterBody2D
class_name Player

@export var movement_speed := 82.0
const CAMERA_ARENA_MARGIN := 32.0
@export var arena_bounds := Rect2(-336.0, -320.0, 672.0, 640.0)
# Local bounds account for the capsule's downward offset.
@export var movement_bounds := Rect2(-332.0, -318.0, 664.0, 630.0)
var intro_locked := false

@onready var body: AnimatedSprite2D = $Body


func _ready() -> void:
	# Camera limits use world coordinates; movement bounds use arena coordinates.
	var arena := get_parent() as Node2D
	var camera: Camera2D = $Camera2D
	var top_left := arena.to_global(arena_bounds.position) - Vector2.ONE * CAMERA_ARENA_MARGIN
	var bottom_right := arena.to_global(arena_bounds.end) + Vector2.ONE * CAMERA_ARENA_MARGIN
	camera.limit_left = roundi(top_left.x)
	camera.limit_top = roundi(top_left.y)
	camera.limit_right = roundi(bottom_right.x)
	camera.limit_bottom = roundi(bottom_right.y)
	camera.make_current()
	camera.reset_smoothing()


func _physics_process(_delta: float) -> void:
	if intro_locked:
		velocity = Vector2.ZERO
		return
	var input_direction := _get_movement_input()
	velocity = input_direction * movement_speed
	move_and_slide()
	position = position.clamp(movement_bounds.position, movement_bounds.end)
	_update_animation(input_direction)


func set_movement_bounds(bounds: Rect2) -> void:
	movement_bounds = bounds


func _get_movement_input() -> Vector2:
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	)
	return direction.normalized()


func _update_animation(input_direction: Vector2) -> void:
	var next_animation: StringName = &"run" if not input_direction.is_zero_approx() else &"idle"
	if body.animation != next_animation:
		body.play(next_animation)
	if not is_zero_approx(input_direction.x):
		body.flip_h = input_direction.x < 0.0
