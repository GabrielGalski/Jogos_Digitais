extends Node2D
## A short in-world reward callout that rises from the defeated source.

# The 128 px source settles at 12 logical px, shown as 36 px in the 3x window.
const POP_SCALE := 0.12
const START_SCALE := 0.07
const SETTLED_SCALE := 0.09375

@onready var booster: Sprite2D = $Booster
@onready var item_name: Label = $ItemName


func play(anchor: Vector2, reward_name: String) -> void:
	global_position = anchor
	item_name.text = reward_name
	booster.scale = Vector2.ONE * START_SCALE
	booster.modulate = Color(1.0, 1.0, 1.0, 0.0)
	item_name.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var pop := create_tween().set_parallel(true)
	pop.tween_property(booster, ^"scale", Vector2.ONE * POP_SCALE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(booster, ^"modulate:a", 1.0, 0.07)
	pop.tween_property(item_name, ^"modulate:a", 1.0, 0.10)
	await pop.finished

	var rise := create_tween().set_parallel(true)
	rise.tween_property(self, ^"global_position", anchor + Vector2(0.0, -10.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rise.tween_property(booster, ^"scale", Vector2.ONE * SETTLED_SCALE, 0.22).set_ease(Tween.EASE_OUT)
	await rise.finished

	var leave := create_tween().set_parallel(true)
	leave.tween_property(booster, ^"modulate:a", 0.0, 0.16)
	leave.tween_property(item_name, ^"modulate:a", 0.0, 0.16)
	leave.tween_property(self, ^"global_position", anchor + Vector2(0.0, -16.0), 0.16).set_ease(Tween.EASE_IN)
	await leave.finished
	queue_free()
