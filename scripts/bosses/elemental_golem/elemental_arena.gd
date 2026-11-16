extends Node2D
## Composition root for the castle encounter, its arrival, defeat and return.

const LAYOUT: Script = preload("res://scripts/bosses/elemental_golem/arena_layout.gd")
const BOSS: Script = preload("res://scripts/bosses/elemental_golem/elemental_golem.gd")
const STATE: Script = preload("res://scripts/bosses/elemental_golem/player_state.gd")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const KIT: Script = preload("res://scripts/combat/player_gameplay_kit.gd")
const GATE: Script = preload("res://scripts/dungeon/warp_gate.gd")
const WARP_ART: Texture2D = preload("res://assets/tiles/structures/warp.png")
const TRANSITION: Script = preload("res://scripts/visual/warp_transition.gd")
const DEFEAT: Script = preload("res://scripts/visual/player_defeat.gd")
const PLAYER_HUD: PackedScene = preload("res://scenes/ui/player_life_hud.tscn")
const BOSS_BAR: PackedScene = preload("res://scenes/ui/asterion_boss_bar.tscn")
@export var fall_invulnerability_duration: float = 1.0
@export var platform_dash_distance: float = 128.0
@export_file("*.ldtk") var map_path: String = "res://monster_booster.ldtk"
@export var level_name: String = "Room_4_Elemental"
var entry_player_state: Dictionary = {}
var return_controller: Node = null
var boss_already_defeated: bool = false
var boss_remains_state: Dictionary = {}
var boss_remains: Sprite2D = null
var player: Player = null
var boss: CharacterBody2D = null
var layout: Node2D = null
var projectiles: Node2D = null
var entrance: Node2D = null
var defeat: CanvasLayer = null
var transition: CanvasLayer = null
var boss_bar: Control = null
var entry_complete: bool = false
var battle_started: bool = false
var won: bool = false
var last_safe_position: Vector2 = Vector2.ZERO
var _leaving: bool = false


func _ready() -> void:
	process_physics_priority = 5
	add_to_group(&"scene_jump_controllers")
	if is_instance_valid(return_controller): return_controller.set("active_arena",self)
	layout = LAYOUT.new() as Node2D
	layout.name = "CastleLayout"
	if not bool(layout.call("load_map",map_path,level_name)):
		layout.free()
		return
	add_child(layout)
	var arena_bounds: Rect2 = layout.get("bounds") as Rect2
	var entry_point: Vector2 = layout.get("entrance") as Vector2
	projectiles = Node2D.new()
	projectiles.name = "BossAttacks"
	add_child(projectiles)
	player = PLAYER.instantiate() as Player
	player.name = "Nox"
	player.position = entry_point
	player.movement_speed = 94.3
	player.dash_duration = platform_dash_distance / player.dash_speed
	player.arena_bounds = arena_bounds
	player.movement_bounds = arena_bounds.grow(-10.0)
	player.intro_locked = true
	add_child(player)
	player.body.z_index = 0
	var kit: Node2D = KIT.new() as Node2D
	kit.name = "GameplayKit"
	# Same rig/zoom as the world, with room for the entrance to stay centred.
	kit.set("world_bounds",Rect2(to_global(arena_bounds.position),arena_bounds.size*global_scale).grow(LAYOUT.CAMERA_MARGIN))
	player.add_child(kit)
	player.get_node("BoosterShooter").set("z_index",-2)
	STATE.apply(player,entry_player_state)
	entrance = GATE.new() as Node2D
	entrance.name = "EntranceWarp"
	entrance.call("configure",layout.get("entrance_data"),WARP_ART)
	add_child(entrance)
	entrance.set("actor",player)
	entrance.connect("travel_requested",_on_return_requested)
	player.position = entrance.call("spawn_position") as Vector2
	last_safe_position = player.position
	player.set_respawn_position(player.position)
	boss = BOSS.new() as CharacterBody2D
	boss.name = "ElementalGolem"
	boss.call("configure",player,layout,projectiles)
	add_child(boss)
	boss.connect("health_changed",_on_boss_health)
	boss.connect("died",_on_boss_defeated)
	boss.connect("defeat_animation_finished",_create_boss_remains)
	if boss_already_defeated or not boss_remains_state.is_empty():
		won = true
		boss.call("restore_defeated")
		_create_boss_remains()
	_build_hud()
	defeat = DEFEAT.new() as CanvasLayer
	defeat.name = "PlayerDefeat"
	defeat.set("exit_action",leave_arena)
	add_child(defeat)
	defeat.call("bind_player",player,self)
	_capture_checkpoint()
	transition = TRANSITION.new() as CanvasLayer
	transition.name = "WarpTransition"
	add_child(transition)
	transition.connect("finished",_on_transition_finished)
	transition.call("play",true,player)


func _build_hud() -> void:
	var player_hud: CanvasLayer = PLAYER_HUD.instantiate() as CanvasLayer
	add_child(player_hud)
	player_hud.call("bind_player",player)
	var hud: CanvasLayer = CanvasLayer.new()
	hud.name = "BossHUD"
	hud.layer = 55
	add_child(hud)
	var interface: Control = Control.new()
	interface.name = "Interface"
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(interface)
	boss_bar = BOSS_BAR.instantiate() as Control
	interface.add_child(boss_bar)
	(boss_bar.get_node("Name") as Label).text = "Golem Elemental"
	_on_boss_health(float(boss.get("health")),float(boss.get("max_health")))


func _physics_process(_delta: float) -> void:
	if not entry_complete or player.dead or player.intro_locked or _leaving: return
	var feet: Vector2 = player.to_global(Vector2(0,3))
	if bool(layout.call("supports_feet",feet)):
		var safe_feet: Vector2 = layout.call("recovery_feet",feet) as Vector2
		last_safe_position = to_local(safe_feet-(feet-player.global_position))
	else:
		if not player.is_dashing(): _recover_from_void()
		return
	var hall: Rect2 = layout.get("hall") as Rect2
	if not battle_started and not won and player.position.y < hall.position.y-4.0:
		battle_started = true
		boss_bar.show()
		boss.call("begin")


func _recover_from_void() -> void:
	player.receive_fall_damage()
	# An empty final block uses the regular defeat flow; living players stay in battle.
	if player.dead: return
	if is_instance_valid(player.parry): player.parry.call("cancel")
	player.position = last_safe_position
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.impact_control_lock = 0.12
	player.contact_slow_remaining = 0.0
	player.contact_slow_factor = 1.0
	player.dash_remaining = 0.0
	player.dash_camera_strength = 0.0
	player.body.end_roll()
	player.snap_floor_height()
	player.reset_physics_interpolation()
	player.grant_fall_recovery(fall_invulnerability_duration)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()


func _on_boss_health(current: float, maximum: float) -> void:
	if boss_bar == null: return
	var bar: Range = boss_bar.get_node("HP") as Range
	bar.max_value = maximum
	bar.value = current


func _on_boss_defeated(_actor: Node2D) -> void:
	won = true
	boss_bar.hide()
	var visual: AnimatedSprite2D = boss.get("sprite") as AnimatedSprite2D
	boss_remains_state = {"element":int(boss.get("element")),
		"transform":boss.transform*visual.transform,"offset":visual.offset,
		"flip_h":visual.flip_h,"z_index":boss.z_index+visual.z_index}
	_capture_checkpoint()
	if is_instance_valid(return_controller): return_controller.set("boss_defeated",true)


func _capture_checkpoint() -> void:
	if not is_instance_valid(defeat): return
	defeat.call("capture_checkpoint",{"return_controller":return_controller,
		"boss_already_defeated":won,"boss_remains_state":boss_remains_state})


func _create_boss_remains() -> void:
	if boss_remains_state.is_empty() or is_instance_valid(boss_remains): return
	var frames: SpriteFrames = BOSS.FRAMES[int(boss_remains_state.element)]
	boss_remains = Sprite2D.new()
	boss_remains.name = "ElementalGolemRemains"
	boss_remains.texture = frames.get_frame_texture(&"die",frames.get_frame_count(&"die")-1)
	boss_remains.transform = boss_remains_state.transform as Transform2D
	boss_remains.offset = boss_remains_state.offset as Vector2
	boss_remains.flip_h = bool(boss_remains_state.flip_h)
	boss_remains.z_index = int(boss_remains_state.z_index)
	boss_remains.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	boss_remains.add_to_group(&"room_boss_remains")
	add_child(boss_remains)
	boss.hide()


func _on_return_requested(_gate: Node2D) -> void:
	leave_arena.call_deferred()


func request_scene_jump() -> void:
	leave_arena()


func leave_arena() -> void:
	if _leaving: return
	_leaving = true
	entry_complete = false
	boss.call("stop_combat")
	if player.dead:
		_return_to_world()
	else:
		transition.call("play",false,player)


func _on_transition_finished(arriving: bool) -> void:
	if arriving:
		player.intro_locked = false
		entry_complete = true
	else:
		_return_to_world()


func _return_to_world() -> void:
	var state: Dictionary = STATE.capture(player,player.dead)
	if is_instance_valid(return_controller):
		return_controller.call("return_to_world",self,state,won)
		return
	# F6 preview has no suspended overworld; use the authored main map.
	get_tree().paused = false
	Engine.time_scale = 1.0
	var packed: PackedScene = load("res://scenes/maps/open_world.tscn") as PackedScene
	var world: Node = packed.instantiate()
	world.set("entry_player_state",state)
	get_parent().add_child(world)
	get_tree().current_scene = world
	queue_free()
