class_name MinotaurAI
extends MinionAI

@export_category("Minotaur")
@export var empowered_by_elite: bool = false
@export var influence_source: StringName = &""
@export var empowered_attack_id: StringName = &"walk_attack"
@export var normal_speed_multiplier: float = 1.0
@export var empowered_speed_multiplier: float = 1.85


func _ready() -> void:
	super._ready()
	if minion_profile.attack_id == &"contact_attack":
		minion_profile.attack_id = &"minotaur_contact"


func apply_elite_influence(source: StringName = &"asterion") -> void:
	empowered_by_elite = true
	influence_source = source
	minion_profile.can_attack_while_moving = true
	minion_profile.attack_id = empowered_attack_id
	reset_decision_timer()


func clear_elite_influence() -> void:
	empowered_by_elite = false
	influence_source = &""
	minion_profile.can_attack_while_moving = false
	minion_profile.attack_id = &"minotaur_contact"
	reset_decision_timer()


func speed_multiplier() -> float:
	return empowered_speed_multiplier if empowered_by_elite else normal_speed_multiplier
