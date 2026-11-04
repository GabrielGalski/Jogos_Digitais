extends Node
## Development-only navigation. Scene controllers retain their own staged skips.

const WORLD_SCENE: String = "res://scenes/maps/open_world.tscn"
const SPIRIT_SCENE: String = "res://scenes/dungeon/ldtk_arena.tscn"
const ASTERION_SCENE: String = "res://scenes/tutorial_arena.tscn"
var _dispatch_queued: bool = false
var _requested_scene: WeakRef = null
var _swapping: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode != KEY_TAB and key.keycode != KEY_TAB:
		return
	get_viewport().set_input_as_handled()
	request_jump()


func request_jump() -> void:
	if _dispatch_queued or _swapping or get_tree().current_scene == null:
		return
	_dispatch_queued = true
	_requested_scene = weakref(get_tree().current_scene)
	_dispatch.call_deferred()


func _dispatch() -> void:
	_dispatch_queued = false
	var scene: Node = get_tree().current_scene
	if scene == null or _requested_scene == null or scene != _requested_scene.get_ref():
		return
	for controller: Node in get_tree().get_nodes_in_group(&"scene_jump_controllers"):
		if controller == scene or scene.is_ancestor_of(controller):
			controller.call("request_scene_jump")
			return
	# F6 previews and legacy scenes can always return to the current playable map.
	travel_to_scene(scene, WORLD_SCENE)


func travel_to_scene(source: Node, destination: String, subject: Player = null) -> bool:
	if _swapping or not is_instance_valid(source) or not ResourceLoader.exists(destination, "PackedScene"):
		return false
	var packed: PackedScene = load(destination) as PackedScene
	if packed == null:
		return false
	var next_scene: Node = packed.instantiate()
	if next_scene == null:
		return false
	if is_instance_valid(subject) and not subject.dead and "entry_player_state" in next_scene:
		var shooter: Node = subject.get_node("BoosterShooter")
		next_scene.set("entry_player_state", {"health": subject.health, "max_health": subject.max_health,
			"dash_charges": subject.dash_charges, "dash_recovery": subject.dash_recovery,
			"card_runtime": shooter.get("card_runtime"), "cooldown": shooter.get("cooldown")})
	_swapping = true
	var outgoing: Node = get_tree().current_scene
	if outgoing == null or (source != outgoing and not outgoing.is_ancestor_of(source)):
		outgoing = source
	var parent: Node = outgoing.get_parent()
	# Exit the old scene first so defeat/modal cleanup cannot pause the new scene.
	parent.remove_child(outgoing)
	get_tree().paused = false
	Engine.time_scale = 1.0
	parent.add_child(next_scene)
	get_tree().current_scene = next_scene
	outgoing.queue_free()
	_swapping = false
	return true
