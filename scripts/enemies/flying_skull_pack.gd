extends "res://scripts/enemies/flying_eye_pack.gd"
## Keep the exact Eye formation, single attack token and three-orb volley.


func _init() -> void:
	actor_script = preload("res://scripts/enemies/flying_skull.gd")
	actor_prefix = "FlyingSkull"
