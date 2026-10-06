class_name CameraVisualizationController
extends Node

const CAMERA_VIEW_ACTION: StringName = &"cycle_camera_view"
const PROJECTION_QUERY_GROUP: StringName = &"camera_projection_query"
const SPATIAL_PRESENTER_SCRIPT: GDScript = preload("res://scripts/camera/camera_spatial_presenter.gd")

@export_node_path("Camera2D") var base_camera_path: NodePath
@export var experimental_views: Array[PackedScene] = []

var _arena: Node2D = null
var _base_camera: Camera2D = null
var _presenter: Node = null
var _view_index: int = 0
var _active_profile: CameraViewProfile = null


func _ready() -> void:
	_arena = get_parent() as Node2D
	var camera_node: Node = get_node_or_null(base_camera_path)
	_base_camera = camera_node as Camera2D
	if _arena == null or _base_camera == null:
		push_error("CameraVisualizationController precisa da arena e de uma Camera2D válida.")
		set_process_unhandled_input(false)
		return

	_presenter = SPATIAL_PRESENTER_SCRIPT.new() as Node
	_presenter.name = "CameraSpatialPresenter"
	add_child(_presenter)
	_presenter.call(&"configure", _arena, _base_camera)
	add_to_group(PROJECTION_QUERY_GROUP)
	_print_current_view()


func _exit_tree() -> void:
	if _presenter != null and is_instance_valid(_presenter):
		_presenter.call(&"deactivate")


func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or key_event.echo:
		return
	if not key_event.is_action_pressed(CAMERA_VIEW_ACTION):
		return
	if not _can_switch_view():
		return

	_cycle_view()
	get_viewport().set_input_as_handled()


func is_spatial_view_active() -> bool:
	if _presenter == null or not is_instance_valid(_presenter):
		return false
	return bool(_presenter.call(&"is_active"))


func screen_to_world(screen_position: Vector2) -> Vector2:
	if not is_spatial_view_active():
		return Vector2.INF
	var projected: Variant = _presenter.call(&"screen_to_world", screen_position)
	return projected as Vector2 if projected is Vector2 else Vector2.INF


func visible_world_rect() -> Rect2:
	if not is_spatial_view_active():
		return Rect2()
	var projected: Variant = _presenter.call(&"visible_world_rect")
	return projected as Rect2 if projected is Rect2 else Rect2()


func _can_switch_view() -> bool:
	var entrance_state: Variant = _arena.get("entrance_complete")
	if entrance_state != null and not bool(entrance_state):
		return false
	var player: Node = _arena.get_node_or_null("Mox")
	if player == null:
		return true
	var input_locked: Variant = player.get("intro_locked")
	return input_locked == null or not bool(input_locked)


func _cycle_view() -> void:
	if _base_camera == null or experimental_views.is_empty():
		return

	_view_index = wrapi(_view_index + 1, 0, experimental_views.size() + 1)
	_remove_active_profile()

	if _view_index == 0:
		_presenter.call(&"deactivate")
		_print_current_view()
		return

	var packed_profile: PackedScene = experimental_views[_view_index - 1]
	var instance: Node = packed_profile.instantiate()
	var profile: CameraViewProfile = instance as CameraViewProfile
	if profile == null:
		instance.queue_free()
		push_error("A cena de visualização precisa ter CameraViewProfile como raiz.")
		_view_index = 0
		_presenter.call(&"deactivate")
		return

	_active_profile = profile
	add_child(_active_profile)
	_presenter.call(&"activate", _active_profile)
	_print_current_view()


func _remove_active_profile() -> void:
	if _active_profile == null or not is_instance_valid(_active_profile):
		return
	_active_profile.queue_free()
	_active_profile = null


func _print_current_view() -> void:
	if _view_index == 0:
		print("Visualização de câmera: Base 2D")
		return
	if _active_profile == null:
		return
	print(
		"Visualização de câmera: ",
		_active_profile.display_name,
		" — elevação ortográfica real de ",
		_active_profile.elevation_degrees,
		" graus"
	)
