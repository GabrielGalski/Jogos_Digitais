extends Area2D
class_name BoosterPickup

signal collected(pickup: BoosterPickup)

@export var proximity_radius := 16.0

var target: Player
var collected_state := false


func _ready() -> void:
	add_to_group(&"booster_pickups")
	body_entered.connect(_on_body_entered)


func setup(player: Player) -> void:
	target = player


func _physics_process(_delta: float) -> void:
	if collected_state or not is_instance_valid(target):
		return
	if global_position.distance_squared_to(target.global_position) <= proximity_radius * proximity_radius:
		_collect()


func is_collected() -> bool:
	return collected_state


func _on_body_entered(body: Node2D) -> void:
	if body == target:
		_collect()


func _collect() -> void:
	if collected_state:
		return
	collected_state = true
	hide()
	remove_from_group(&"booster_pickups")
	set_deferred(&"monitoring", false)
	collected.emit(self)
	queue_free()
