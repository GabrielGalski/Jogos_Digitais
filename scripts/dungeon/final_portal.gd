extends Node2D
## The six cleared altars unlock the route to the Dragon's clearing.

signal progress_changed(completed: int, active_runes: int, charged: bool)

const GATE: Script = preload("res://scripts/dungeon/warp_gate.gd")
const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
const REQUIRED_ALTARS: int = 6
const RUNES_PER_ALTAR: int = 4
const WARP_SCALE: float = 0.9375

var completed_altars: int = 0
var active_runes: int = 0
var ready_for_final_battle: bool = false
var ground_height: float = 0.0
var _world: Node2D
var _gate: Node2D
var _landing: Vector2 = Vector2.INF
var _tracked: Dictionary[String, Node2D] = {}
var _completed: Dictionary[String, bool] = {}


func configure(world: Node2D, layers: Array, encounters: Array) -> void:
	_world = world
	position = castle_position(layers)
	ground_height = float(world.call("_terrain_and_warp_height", world.to_global(position)))
	_landing = _find_dragon_landing()
	add_to_group(&"final_portals")

	_gate = GATE.new()
	_gate.name = "FinalWarp"
	_gate.call("configure", {
		"position": Vector2.ZERO, "WarpId": "final", "Interact": true,
		"ShowActivation": true, "DisplayScale": WARP_SCALE, "GroundHeight": ground_height,
		"RequiredCondition": "all_six_altars_clear",
	})
	_gate.z_index = 1
	_gate.set("actor", world.get_node("Nox"))
	_gate.set("gameplay", world.get_node("Gameplay"))
	_gate.set("travel_available", _route_available)
	_gate.connect("travel_requested", _on_travel_requested)
	add_child(_gate)

	for encounter: Node2D in encounters:
		var id: String = str(encounter.get("encounter_id"))
		if id.is_empty() or _tracked.has(id):
			continue
		_tracked[id] = encounter
		encounter.connect("cleared", _on_altar_cleared.bind(id))
		if int(encounter.get("phase")) == 2:
			_completed[id] = true
	_refresh_progress()


static func castle_position(layers: Array) -> Vector2:
	var castle: Rect2 = Rect2()
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "ElevationArea" or not bool(ENTITIES.fields(entity).get("Enabled", true)):
				continue
			var area: Rect2 = ENTITIES.entity_rect(entity, offset)
			if area.get_area() > castle.get_area():
				castle = area
	return Vector2(castle.get_center().x, castle.position.y + 288.0)


func _find_dragon_landing() -> Vector2:
	var dragon: Node2D = _world.get_node_or_null("DragonEncounter") as Node2D
	if dragon == null:
		return Vector2.INF
	var arena: Rect2 = dragon.get("arena_bounds") as Rect2
	for offset: Vector2 in [Vector2(64, 68), Vector2(-64, 68), Vector2(64, -68), Vector2(-64, -68)]:
		var candidate: Vector2 = dragon.global_position + offset
		if arena.grow(-12.0).has_point(candidate) and bool(_world.call("is_ground_surface_point", candidate)):
			return candidate
	return Vector2.INF


func _route_available() -> bool:
	return _landing.is_finite() and bool(_world.get("entry_complete"))


func _on_travel_requested(gate: Node2D) -> void:
	_world.call_deferred("travel_inside_room", gate, _landing)


func _on_altar_cleared(id: String) -> void:
	if not _tracked.has(id) or _completed.has(id):
		return
	_completed[id] = true
	_refresh_progress()


func _refresh_progress() -> void:
	completed_altars = mini(_completed.size(), REQUIRED_ALTARS)
	active_runes = completed_altars * RUNES_PER_ALTAR
	ready_for_final_battle = _tracked.size() == REQUIRED_ALTARS and completed_altars == REQUIRED_ALTARS
	_world.get_node("Gameplay").call("set_condition", "all_six_altars_clear", ready_for_final_battle)
	progress_changed.emit(completed_altars, active_runes, ready_for_final_battle)
