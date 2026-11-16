extends Node
## Owns the unlocked portal and suspends the actual world for a lossless return.
## No global save state: the world retains its completed altars and authored terrain.

const ENCOUNTER_ID: String = "room_2_river_south"
const ARENA_PATH: String = "res://scenes/bosses/elemental_golem_arena.tscn"
const GATE: Script = preload("res://scripts/dungeon/warp_gate.gd")
const TRANSITION: Script = preload("res://scripts/visual/warp_transition.gd")
const STATE: Script = preload("res://scripts/bosses/elemental_golem/player_state.gd")
const ART: Texture2D = preload("res://assets/tiles/structures/warp.png")
var world: Node2D = null
var subject: Player = null
var encounter: Node2D = null
var pedestal: Node2D = null
var gate: Node2D = null
var active_arena: Node2D = null
var boss_defeated: bool = false
var _busy: bool = false
var _suspended: Array[Dictionary] = []
var _layers: Array[CanvasLayer] = []


func configure(room: Node2D, encounters: Array, pedestals: Array) -> void:
	world = room
	subject = room.get_node("Nox") as Player
	for candidate: Node2D in encounters:
		if str(candidate.get("encounter_id")) == ENCOUNTER_ID: encounter = candidate
	if encounter == null: return
	for candidate: Node2D in pedestals:
		if candidate.get("encounter") == encounter:
			pedestal = candidate
			break
	if pedestal == null:
		# Adapter order and encounter identity are stable even on older pedestal art.
		var center: Vector2 = encounter.get("arena_center") as Vector2
		for candidate: Node2D in pedestals:
			if candidate.position.distance_to(center) < 2.0: pedestal = candidate
	encounter.connect("cleared",unlock)


func unlock() -> void:
	if is_instance_valid(gate) or not is_instance_valid(pedestal): return
	var point: Vector2 = pedestal.position
	for offset: Vector2 in [Vector2(0,72),Vector2(0,-72),Vector2(-72,0),Vector2(72,0),Vector2(-48,48),Vector2(48,-48)]:
		if bool(world.call("is_ground_surface_point",world.to_global(pedestal.position+offset))):
			point = pedestal.position+offset
			break
	gate = GATE.new() as Node2D
	gate.name = "ElementalBossWarp"
	gate.call("configure",{"position":point,"WarpId":"elemental_golem","Interact":true,
		"TargetScene":ARENA_PATH,"DisplayScale":0.5},ART)
	world.add_child(gate)
	gate.set("actor",subject)
	gate.set("gameplay",world.get("_gameplay"))
	gate.connect("travel_requested",_request_entry)


func _request_entry(_gate: Node2D) -> void:
	enter_arena.call_deferred()


func enter_arena() -> void:
	if _busy or subject.dead or subject.intro_locked or not is_instance_valid(gate): return
	var packed: PackedScene = load(ARENA_PATH) as PackedScene
	if packed == null: return
	_busy = true
	world.set("_travel_busy",true)
	world.set("entry_complete",false)
	var departure: CanvasLayer = TRANSITION.new() as CanvasLayer
	departure.name = "BossDeparture"
	add_child(departure)
	departure.call("play",false,subject)
	await departure.finished
	var state: Dictionary = STATE.capture(subject)
	departure.queue_free()
	_suspend_world()
	active_arena = packed.instantiate() as Node2D
	active_arena.set("entry_player_state",state)
	active_arena.set("return_controller",self)
	active_arena.set("boss_already_defeated",boss_defeated)
	world.get_parent().add_child(active_arena)
	get_tree().current_scene = active_arena


func _suspend_world() -> void:
	_suspended.clear()
	_layers.clear()
	var nodes: Array[Node] = [world]
	nodes.append_array(world.find_children("*","",true,false))
	for node: Node in nodes:
		if node.is_queued_for_deletion(): continue
		var record: Dictionary = {"node":node,"process_mode":node.process_mode}
		if node is CollisionObject2D:
			var body: CollisionObject2D = node as CollisionObject2D
			record["collision_layer"] = body.collision_layer
			record["collision_mask"] = body.collision_mask
			body.collision_layer = 0
			body.collision_mask = 0
		if node is CanvasLayer and (node as CanvasLayer).visible:
			_layers.append(node as CanvasLayer)
			(node as CanvasLayer).hide()
		_suspended.append(record)
		node.process_mode = Node.PROCESS_MODE_DISABLED
	world.hide()


func return_to_world(arena: Node2D, state: Dictionary, won: bool) -> void:
	if not is_instance_valid(world): return
	boss_defeated = boss_defeated or won
	for record: Dictionary in _suspended:
		if not is_instance_valid(record.get("node")): continue
		var node: Node = record.node as Node
		node.process_mode = int(record.process_mode) as Node.ProcessMode
		if node is CollisionObject2D:
			(node as CollisionObject2D).collision_layer = int(record.collision_layer)
			(node as CollisionObject2D).collision_mask = int(record.collision_mask)
	for layer: CanvasLayer in _layers:
		if is_instance_valid(layer): layer.show()
	_suspended.clear()
	_layers.clear()
	STATE.apply(subject,state)
	subject.intro_locked = true
	subject.contact_invulnerability = 1.5
	subject.velocity = Vector2.ZERO
	subject.knockback_velocity = Vector2.ZERO
	subject.position = gate.call("spawn_position") as Vector2
	subject.snap_floor_height()
	subject.reset_physics_interpolation()
	world.show()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().current_scene = world
	var camera: Camera2D = subject.get_node("Camera2D") as Camera2D
	camera.make_current()
	camera.reset_smoothing()
	world.call("_start_warp_effect",true)
	_busy = false
	active_arena = null
	arena.queue_free()
