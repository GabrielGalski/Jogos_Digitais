class_name AsterionAI
extends EliteAI

@export_category("Asterion")
@export var skybreaker_min_distance: float = 128.0
@export var skybreaker_attack_id: StringName = &"skybreaker"
@export var melee_attack_id: StringName = &"asterion_melee"
@export var influence_id: StringName = &"minotaur_rush"
@export var requires_landing_validation: bool = true


func _ready() -> void:
	if elite_profile == null:
		elite_profile = EliteAIProfile.new()
	elite_profile.elite_id = &"asterion"
	elite_profile.close_attack_id = melee_attack_id
	elite_profile.special_attack_id = skybreaker_attack_id
	elite_profile.special_min_distance = skybreaker_min_distance
	profile = elite_profile
	super._ready()


func elite_influence_id() -> StringName:
	return influence_id


func _can_use_special(observation: EnemyAIObservation) -> bool:
	if requires_landing_validation and not observation.landing_position_valid:
		return false
	return super._can_use_special(observation)
