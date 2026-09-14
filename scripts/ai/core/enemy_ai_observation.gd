class_name EnemyAIObservation
extends RefCounted

var actor_id: StringName = &""
var self_position: Vector2 = Vector2.ZERO
var self_radius: float = 8.0
var target_position: Vector2 = Vector2.ZERO
var target_velocity: Vector2 = Vector2.ZERO
var target_valid: bool = false
var target_visible: bool = false
var target_reachable: bool = false
var objective: int = EnemyAIEnums.Objective.IDLE
var objective_position: Vector2 = Vector2.ZERO
var has_objective_position: bool = false
var chamber_active: bool = true
var route_valid: bool = false
var route_direction: Vector2 = Vector2.ZERO
var fallback_position: Vector2 = Vector2.ZERO
var has_fallback_position: bool = false
var landing_position_valid: bool = false
var distance_to_target: float = 0.0
var line_of_sight_clear: bool = false
var neighbors: Array[EnemyAINeighbor] = []
var attack_slots: Array[EnemyAISlot] = []


func refresh_distance() -> void:
	distance_to_target = self_position.distance_to(target_position) if target_valid else INF


func available_slot(actor_role: int) -> EnemyAISlot:
	var best_slot: EnemyAISlot = null
	var best_distance: float = INF
	for slot: EnemyAISlot in attack_slots:
		if slot == null or not slot.is_available_for(actor_role):
			continue
		var slot_distance: float = self_position.distance_to(slot.position)
		if slot_distance < best_distance:
			best_distance = slot_distance
			best_slot = slot
	return best_slot


func nearest_fallback() -> Vector2:
	if has_fallback_position:
		return fallback_position
	return self_position
