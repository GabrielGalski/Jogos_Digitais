extends Node2D

const KIT: Script = preload("res://scripts/combat/player_gameplay_kit.gd")
const BOSS: Script = preload("res://scripts/bosses/vampire/vampire_boss.gd")
const STATE: Script = preload("res://scripts/bosses/elemental_golem/player_state.gd")
const LIGHTING: Script = preload("res://scripts/visual/room_lighting.gd")
const LIGHTING_PROFILE: Resource = preload("res://resources/visual/room_1_lighting.tres")
const LIGHTING_SETUPS: Resource = preload("res://resources/visual/room_lighting_setups.tres")
const DEFEAT: Script = preload("res://scripts/visual/player_defeat.gd")
const CARD_TABLE: PackedScene = preload("res://scenes/cards/card_table.tscn")
const JUMPER: Script = preload("res://scripts/debug/scene_jumper.gd")
const MAP_SOURCE: Script = preload("res://scripts/bosses/elemental_golem/arena_map_source.gd")
const MAP_TILES: Script = preload("res://scripts/bosses/elemental_golem/arena_tiles.gd")
const STARFIELD: Shader = preload("res://shaders/vampire_starfield.gdshader")
const FACADE_FADE: Shader = preload("res://shaders/vampire_facade_fade.gdshader")

const MAP_PATH: String = "res://monster_booster.ldtk"
const LEVEL_NAME: String = "Room_5_Vampire"
## Inner edges of the painted room, passage and stairs, in LDtk room coordinates.
const ARENA: Rect2 = Rect2(80, 80, 328, 336)
const HALL: Rect2 = Rect2(216, 416, 64, 88)
const STAIRS: Rect2 = Rect2(200, 504, 96, 112)
const GATE: Rect2 = Rect2(216, 412, 64, 8)
const WALL_THICKNESS: float = 8.0
const PERIMETER: Array[Vector2] = [
	Vector2(80, 80), Vector2(408, 80), Vector2(408, 416), Vector2(280, 416),
	Vector2(280, 504), Vector2(296, 504), Vector2(296, 616), Vector2(200, 616),
	Vector2(200, 504), Vector2(216, 504), Vector2(216, 416), Vector2(80, 416),
]

var entry_player_state: Dictionary = {}
var battle_started: bool = false
var won: bool = false
var boss: BOSS
var _gate: StaticBody2D
var _gate_locked: bool = false
var _starfield: ShaderMaterial
@onready var player: Player = $Nox
@onready var _boss_bar: Control = $BossHUD/Interface/Boss
@onready var _health_bar: Range = $BossHUD/Interface/Boss/HP


func _ready() -> void:
	var arrival: Vector2 = _load_room()
	if not arrival.is_finite():
		set_physics_process(false)
		return
	add_to_group(&"scene_jump_controllers")
	process_physics_priority = 5
	_build_collision()
	player.position = arrival
	player.set_respawn_position(arrival)
	player.movement_speed = 94.3
	player.arena_bounds = ARENA.merge(STAIRS)
	player.movement_bounds = player.arena_bounds
	player.body.z_index = 0
	player.get_node("BoosterShooter").set("z_index", -2)
	var kit: Node2D = KIT.new() as Node2D
	kit.name = "GameplayKit"
	kit.set("world_bounds", Rect2(to_global(player.arena_bounds.position), player.arena_bounds.size))
	player.add_child(kit)
	STATE.apply(player, entry_player_state)
	kit.call("reveal")
	$PlayerHUD.call("bind_player", player)
	var lighting: CanvasLayer = LIGHTING.new() as CanvasLayer
	lighting.name = "RoomLighting"
	lighting.set("profile", LIGHTING_PROFILE)
	lighting.set("setups", LIGHTING_SETUPS)
	lighting.set("subject", player)
	add_child(lighting)

	boss = BOSS.new()
	boss.name = "Vampiro"
	boss.position = ARENA.get_center()
	boss.z_index = 2
	boss.configure(player, ARENA, $BossAttacks)
	add_child(boss)
	boss.health_changed.connect(_on_boss_health_changed)
	boss.defeated.connect(_on_boss_defeated)
	_on_boss_health_changed(boss.health, boss.max_health)
	(_boss_bar.get_node("Name") as Label).text = "Vampiro"
	var defeat: CanvasLayer = DEFEAT.new() as CanvasLayer
	defeat.name = "PlayerDefeat"
	defeat.set("exit_action", request_scene_jump)
	add_child(defeat)
	defeat.call("bind_player", player, self)
	defeat.call("capture_checkpoint")
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	_build_starfield()


func _load_room() -> Vector2:
	var map: Dictionary = MAP_SOURCE.read(MAP_PATH, LEVEL_NAME)
	if not bool(map.get("ok", false)):
		push_error(str(map.get("error", "Could not load " + LEVEL_NAME)))
		return Vector2.INF
	var layers: Array = map.layers
	var spawn: Vector2 = Vector2.ZERO
	var count: int = 0
	for layer: Dictionary in layers:
		if layer.__identifier != "Gameplay":
			continue
		var grid: int = int(layer.__gridSize)
		var columns: int = int(layer.__cWid)
		var offset: Vector2 = Vector2(float(layer.__pxTotalOffsetX), float(layer.__pxTotalOffsetY))
		var cells: Array = layer.intGridCsv
		for index: int in range(cells.size()):
			if int(cells[index]) == 4:
				spawn += Vector2(index % columns, floori(float(index) / columns)) * grid + offset + Vector2.ONE * grid * 0.5
				count += 1
	if count == 0 or not STAIRS.has_point(spawn / float(count)):
		push_error("Room_5_Vampire needs a Gameplay Start in the southern entrance.")
		return Vector2.INF
	var sources: Dictionary = {}
	for definition: Dictionary in map.tilesets:
		sources[int(definition.uid)] = definition
	var painted: Node2D = Node2D.new()
	painted.name = "PaintedRoom"
	add_child(painted)
	var tiles: RefCounted = MAP_TILES.new() as RefCounted
	tiles.call("build", painted, layers, sources, Vector2.ZERO)
	var facade_fade: ShaderMaterial = ShaderMaterial.new()
	facade_fade.shader = FACADE_FADE
	facade_fade.set_shader_parameter(&"room_origin", global_position)
	for tile_layer: TileMapLayer in painted.get_children():
		var layer_name: String = str(tile_layer.name)
		if layer_name.begins_with("Walls") or layer_name.begins_with("GroundBase"):
			tile_layer.material = facade_fade
	return spawn / float(count)


func _build_starfield() -> void:
	var sky: CanvasLayer = CanvasLayer.new()
	sky.name = "Starfield"
	sky.layer = -5
	add_child(sky)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_starfield = ShaderMaterial.new()
	_starfield.shader = STARFIELD
	backdrop.material = _starfield
	sky.add_child(backdrop)
	process_priority = 20
	_update_starfield()


func _process(_delta: float) -> void:
	if _starfield != null:
		_update_starfield()


func _update_starfield() -> void:
	var viewport: Viewport = get_viewport()
	var camera: Camera2D = viewport.get_camera_2d()
	if camera == null:
		return
	_starfield.set_shader_parameter(&"view_size", viewport.get_visible_rect().size)
	_starfield.set_shader_parameter(&"camera_drift", camera.get_screen_center_position())
	_starfield.set_shader_parameter(&"world_per_pixel", 1.0 / camera.zoom.x)


func _physics_process(_delta: float) -> void:
	if battle_started or player.dead or player.intro_locked:
		return
	if ARENA.grow(-14.0).has_point(player.position + Vector2(0, 3)):
		battle_started = true
		_set_gate_locked(true)
		boss.begin()
		_boss_bar.show()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or player.dead or player.intro_locked:
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER] or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if get_tree().get_first_node_in_group(&"card_table_modal") == null:
			add_child(CARD_TABLE.instantiate())
			get_viewport().set_input_as_handled()


func is_ground_surface_point(point: Vector2) -> bool:
	var local: Vector2 = to_local(point)
	return (ARENA.has_point(local) or HALL.has_point(local) or STAIRS.has_point(local)) and (not _gate_locked or not GATE.has_point(local))


func is_sword_ground_point(point: Vector2) -> bool:
	return is_ground_surface_point(point)


func request_scene_jump() -> void:
	get_node("/root/SceneJumper").call("travel_to_scene", self, JUMPER.WORLD_SCENE, player)


func _on_boss_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_boss_defeated() -> void:
	won = true
	_boss_bar.hide()
	_set_gate_locked(false)


func _set_gate_locked(locked: bool) -> void:
	_gate_locked = locked
	_gate.set_deferred("collision_layer", 1 if locked else 0)


func _build_collision() -> void:
	var walls: StaticBody2D = StaticBody2D.new()
	walls.name = "ArenaWalls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	for index: int in range(PERIMETER.size()):
		var start: Vector2 = PERIMETER[index]
		var end: Vector2 = PERIMETER[(index + 1) % PERIMETER.size()]
		_wall_shape(walls, _wall_rect(start, end))
	_gate = StaticBody2D.new()
	_gate.name = "EntranceGate"
	_gate.collision_layer = 0
	_gate.collision_mask = 0
	add_child(_gate)
	_wall_shape(_gate, GATE)


func _wall_shape(body: StaticBody2D, rect: Rect2) -> void:
	var collision: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	collision.position = rect.get_center()
	body.add_child(collision)


func _wall_rect(start: Vector2, end: Vector2) -> Rect2:
	var tangent: Vector2 = (end - start).normalized()
	var outside: Vector2 = Vector2(tangent.y, -tangent.x) * WALL_THICKNESS
	var first: Vector2 = start.min(end) + outside.min(Vector2.ZERO)
	var last: Vector2 = start.max(end) + outside.max(Vector2.ZERO)
	return Rect2(first, last - first)
