extends Node
## Owns only the selected framing. Camera paths, combat and cutscene timing stay separate.

signal distance_changed(index: int)
@export var presets: Resource = preload("res://resources/visual/camera_distance_presets.tres")
const SESSION_KEY: StringName = &"monster_booster_camera_distance_index"

var camera: Camera2D = null
var base_zoom: float = 1.0


func _ready() -> void:
	# Lessons pause simulation, not the presentation selector.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"camera_distance_controllers")
	if not get_tree().has_meta(SESSION_KEY):
		get_tree().set_meta(SESSION_KEY, int(presets.get("default_index")))
	get_tree().set_meta(SESSION_KEY, view_index())
	apply_zoom()


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode != KEY_BACKSPACE and key.keycode != KEY_BACKSPACE:
		return
	if not bool(presets.get("cycling_enabled")) or view_count() < 2:
		return
	# In rooms offering lighting comparisons, Backspace belongs to that selector.
	for selector: Node in get_tree().get_nodes_in_group(&"room_lighting_setup_switchers"):
		if selector.get_viewport() == get_viewport() and bool(selector.call("can_cycle_setups")):
			return
	select_view((view_index() + 1) % view_count())
	get_viewport().set_input_as_handled()


func view_count() -> int:
	return int(presets.call("view_count"))


func view_index() -> int:
	var index: int = int(get_tree().get_meta(SESSION_KEY, int(presets.get("default_index"))))
	return clampi(index, 0, view_count() - 1)


static func reset_session(index: int = -1) -> void:
	var loop: MainLoop = Engine.get_main_loop()
	if index < 0:
		loop.remove_meta(SESSION_KEY)
	else:
		loop.set_meta(SESSION_KEY, index)


func selected_zoom() -> float:
	return base_zoom / float(presets.call("factor_at", view_index()))


func select_view(index: int) -> void:
	get_tree().set_meta(SESSION_KEY, clampi(index, 0, view_count() - 1))
	apply_zoom()
	# Limits/offsets remain owned by each scene; listeners only refit its framing.
	distance_changed.emit(view_index())
	if is_instance_valid(camera):
		camera.reset_smoothing()
		camera.force_update_scroll()


func set_base_zoom(value: float) -> void:
	base_zoom = maxf(value, 0.01)
	apply_zoom()


func apply_zoom(pulse: float = 0.0) -> void:
	if is_instance_valid(camera):
		camera.zoom = Vector2.ONE * selected_zoom() * (1.0 - pulse)
