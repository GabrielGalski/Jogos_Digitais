extends "res://scripts/enemies/flying_eye.gd"
## The original Eye actor, health, damage contract, motion and recoil; only its art differs.


func _init() -> void:
	visual_script = preload("res://scripts/visual/flying_skull_visual.gd")
	species_group = &"flying_skulls"
