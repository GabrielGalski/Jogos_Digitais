extends Resource
## Art-direction alternatives sharing the same camera and gameplay lighting controller.

@export var profiles: Array[Resource] = []
@export_range(0, 16, 1) var default_index: int = 0
@export var cycling_enabled: bool = true


func set_profiles(choices: Array) -> void:
	profiles.assign(choices)
