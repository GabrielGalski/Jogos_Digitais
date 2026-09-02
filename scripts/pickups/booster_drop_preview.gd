extends Node2D
class_name BoosterDropPreview

const BOOSTER_PICKUP_SCENE := preload("res://scenes/pickups/booster_pickup.tscn")

@export var fixed_spawn_position := Vector2(52.0, 24.0)
@export var respawn_delay := 10.0

@onready var target: Player = get_parent().get_node("Player")

var current_pickup: BoosterPickup
var respawn_remaining := -1.0


func _ready() -> void:
	call_deferred(&"_spawn_pickup")


func _process(delta: float) -> void:
	if is_instance_valid(current_pickup) or respawn_remaining < 0.0:
		return
	respawn_remaining = maxf(respawn_remaining - delta, 0.0)
	if is_zero_approx(respawn_remaining):
		_spawn_pickup()


func get_current_pickup() -> BoosterPickup:
	return current_pickup


func get_respawn_remaining() -> float:
	return respawn_remaining


func _spawn_pickup() -> void:
	if is_instance_valid(current_pickup):
		return
	current_pickup = BOOSTER_PICKUP_SCENE.instantiate() as BoosterPickup
	add_child(current_pickup)
	current_pickup.name = "BoosterPickup"
	current_pickup.global_position = fixed_spawn_position
	current_pickup.setup(target)
	current_pickup.collected.connect(_on_pickup_collected)
	respawn_remaining = -1.0


func _on_pickup_collected(pickup: BoosterPickup) -> void:
	if pickup != current_pickup:
		return
	current_pickup = null
	respawn_remaining = respawn_delay
