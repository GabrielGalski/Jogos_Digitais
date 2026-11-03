extends "res://scripts/camera/camera_distance_controller.gd"
## Shared combat framing. Presets never change movement, colliders or cutscene paths.

# Restore the original small-character/shooter framing.
const ZOOM: float = 1.2
const SCREEN_ANCHOR: Vector2 = Vector2(0.5, 0.5)
const FEEDBACK: Script = preload("res://scripts/camera/projectile_camera_feedback.gd")
@export var feedback_profile: Resource = preload("res://resources/visual/projectile_camera_feedback.tres")

var player: Player = null
var world_bounds: Rect2 = Rect2()
var baseline: Vector2 = Vector2.ZERO
var projectile_feedback: RefCounted = FEEDBACK.new() as RefCounted
var projectile_offset: Vector2 = Vector2.ZERO
var _encounter_offset: Vector2 = Vector2.ZERO
var _parry_offset: Vector2 = Vector2.ZERO
var _effects: CombatEffects = null
var _shooter: Node2D = null


func _ready() -> void:
	process_priority = 10
	process_physics_priority = 10
	camera = player.get_node("Camera2D") as Camera2D
	camera.set_meta(&"owns_combat_camera_feedback", true)
	_encounter_offset = camera.offset
	projectile_feedback.set("profile", feedback_profile)
	_shooter = player.get_node("BoosterShooter") as Node2D
	_shooter.connect("shot_fired", _on_shot_fired)
	base_zoom = ZOOM
	super._ready()
	distance_changed.connect(_on_distance_changed)
	camera.drag_horizontal_enabled = false
	camera.drag_vertical_enabled = false
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	get_viewport().size_changed.connect(_fit_frame)
	_fit_frame()
	camera.make_current()
	camera.reset_smoothing()
	camera.force_update_scroll()


func _fit_frame() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size / camera.zoom
	baseline = (Vector2.ONE * 0.5 - SCREEN_ANCHOR) * view + Vector2(0.0, 4.0)
	# Restore the original arena margin as well as zoom and camera offset.
	# The character can drift from centre when the camera reaches a map edge.
	camera.limit_left = floori(world_bounds.position.x - Player.CAMERA_ARENA_MARGIN)
	camera.limit_top = floori(world_bounds.position.y - Player.CAMERA_ARENA_MARGIN)
	camera.limit_right = ceili(world_bounds.end.x + Player.CAMERA_ARENA_MARGIN)
	camera.limit_bottom = ceili(world_bounds.end.y + Player.CAMERA_ARENA_MARGIN)
	if not camera.top_level:
		camera.position = baseline + player.dash_camera_offset


func _process(delta: float) -> void:
	# Entrance owns camera position while top_level; the selected zoom still applies.
	apply_zoom(0.025 * player.dash_camera_strength if not camera.top_level else 0.0)
	if not camera.top_level:
		# Player owns dash kick; Asterion owns camera.offset/rotation for impacts.
		camera.position = baseline + player.dash_camera_offset
	if not _feedback_allowed():
		projectile_feedback.call("reset")
	projectile_offset = (projectile_feedback.call("advance", delta) as Vector2) / camera.zoom
	_compose_offset()


func _physics_process(_delta: float) -> void:
	if camera.top_level:
		return
	camera.position = baseline + player.dash_camera_offset
	# A double dash must not leave Nox below the viewport while smoothing catches up.
	if player.is_dashing():
		camera.reset_smoothing()
		camera.force_update_scroll()


func _on_distance_changed(_index: int) -> void:
	_fit_frame()


func bind_effects(effects: CombatEffects) -> void:
	if is_instance_valid(_effects):
		if _effects.hit_confirmed.is_connected(_on_hit_confirmed):
			_effects.hit_confirmed.disconnect(_on_hit_confirmed)
		if _effects.surface_hit.is_connected(_on_surface_hit):
			_effects.surface_hit.disconnect(_on_surface_hit)
	_effects = effects
	_effects.hit_confirmed.connect(_on_hit_confirmed)
	_effects.surface_hit.connect(_on_surface_hit)


func _feedback_allowed() -> bool:
	return bool(feedback_profile.get("enabled")) and not get_tree().paused and not camera.top_level \
		and not player.intro_locked and not player.dead and not player.is_parry_feedback_active() \
		and bool(get_parent().get("combat_enabled"))


func _on_shot_fired() -> void:
	if _feedback_allowed():
		projectile_feedback.call("shot", _shooter.get("aim_direction") as Vector2)


func _on_hit_confirmed(at: Vector2, direction: Vector2, killed: bool) -> void:
	if _feedback_allowed() and _impact_visible(at):
		projectile_feedback.call("hit", direction, killed)


func _on_surface_hit(at: Vector2, direction: Vector2) -> void:
	if _feedback_allowed() and _impact_visible(at):
		projectile_feedback.call("wall", direction)


func _impact_visible(at: Vector2) -> bool:
	return get_viewport().get_visible_rect().grow(16.0).has_point(camera.get_canvas_transform() * at)


func set_encounter_offset(value: Vector2) -> void:
	_encounter_offset = value
	_compose_offset()


func get_encounter_offset() -> Vector2:
	return _encounter_offset


func set_parry_offset(value: Vector2) -> void:
	_parry_offset = value
	_compose_offset()


func _compose_offset() -> void:
	# Separate ownership prevents a cutscene from saving a transient projectile kick.
	camera.offset = _encounter_offset + _parry_offset + projectile_offset


func _exit_tree() -> void:
	if is_instance_valid(camera):
		camera.offset = _encounter_offset
		camera.remove_meta(&"owns_combat_camera_feedback")
