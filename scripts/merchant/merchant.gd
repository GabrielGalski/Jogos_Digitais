class_name MerchantInteractable
extends Area2D
## The hall's Nox is a Node2D, so proximity uses his feet, not body_entered.

@export var initial_dialogue: DialogueSequence
@onready var interaction_area: CollisionShape2D = $InteractionArea

func can_interact(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or interaction_area.disabled:
		return false
	var rectangle: RectangleShape2D = interaction_area.shape as RectangleShape2D
	if rectangle == null:
		return false
	return Rect2(-rectangle.size * 0.5, rectangle.size).has_point(interaction_area.to_local(actor.global_position))
