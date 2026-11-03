extends Node2D
## Warp arrival only; geometry and the two encounter phases remain scene-owned.

signal entrance_finished
const GAMEPLAY_KIT: Script = preload("res://scripts/combat/player_gameplay_kit.gd")
const SOIL_SURFACE: Script = preload("res://scripts/visual/tutorial_soil_surface.gd")
const WARP_TRANSITION: Script = preload("res://scripts/visual/warp_transition.gd")
const PLAYER_DEFEAT: Script = preload("res://scripts/visual/player_defeat.gd")

var entry_player_state: Dictionary = {}
var entrance_complete: bool = false
@onready var player: Player = $Mox


func _ready() -> void:
	var soil: Node = SOIL_SURFACE.new()
	soil.name = "TutorialSoilSurface"
	add_child(soil)
	var kit: Node2D = GAMEPLAY_KIT.new() as Node2D
	kit.name = "GameplayKit"
	kit.set("world_bounds", Rect2(to_global(player.arena_bounds.position), player.arena_bounds.size * global_scale))
	kit.set("combat_enabled", false)
	player.add_child(kit)
	_restore_player_state()
	var defeat: CanvasLayer = PLAYER_DEFEAT.new() as CanvasLayer
	defeat.name = "PlayerDefeat"
	add_child(defeat)
	defeat.call("bind_player", player, self)
	defeat.call("capture_checkpoint")
	player.set_respawn_position(player.position)
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	var arrival: CanvasLayer = WARP_TRANSITION.new() as CanvasLayer
	arrival.name = "WarpTransition"
	add_child(arrival)
	arrival.call("play", true, player)
	await arrival.finished
	player.intro_locked = false
	entrance_complete = true
	entrance_finished.emit()


func _restore_player_state() -> void:
	if entry_player_state.is_empty():
		return
	player.max_health = float(entry_player_state.get("max_health", player.max_health))
	player.health = clampf(float(entry_player_state.get("health", player.health)), 0.0, player.max_health)
	player.dash_charges = int(entry_player_state.get("dash_charges", player.dash_charges))
	player.dash_recovery = float(entry_player_state.get("dash_recovery", 0.0))
	var shooter: Node = player.get_node("BoosterShooter")
	if entry_player_state.has("card_runtime"):
		shooter.set("card_runtime", entry_player_state.card_runtime)
	shooter.set("cooldown", float(entry_player_state.get("cooldown", 0.0)))
	player.health_changed.emit(player.health, player.max_health)


func is_sword_ground_point(world_point: Vector2) -> bool:
	if not player.arena_bounds.has_point(to_local(world_point)):
		return false
	for boundary_name: String in ["LargeHoleBoundary", "SmallHoleBoundary"]:
		var boundary: CollisionPolygon2D = get_node("ArenaCollision/" + boundary_name) as CollisionPolygon2D
		if Geometry2D.is_point_in_polygon(boundary.to_local(world_point), boundary.polygon):
			return false
	return true
