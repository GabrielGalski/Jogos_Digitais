extends SceneTree
## Physics, independent conditions, LDtk triggers and MonsterShift-compatible commands.
const GAMEPLAY: Script = preload("res://scripts/dungeon/ldtk_gameplay.gd")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
var _failures: Array[String] = []
var _rendered: bool = false


func _initialize() -> void:
	_rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _fields(values: Dictionary) -> Array:
	var result: Array = []
	for key: String in values:
		result.append({"__identifier":key,"__value":values[key]})
	return result


func _control(door_id: String, condition_id: String, pixel: Vector2i, pivot: Vector2 = Vector2.ZERO, enabled: bool = true) -> Dictionary:
	return {"__identifier":"DoorControl","px":[pixel.x,pixel.y],"__pivot":[pivot.x,pivot.y],
		"width":16,"height":128,"fieldInstances":_fields({"DoorId":door_id,"ConditionId":condition_id,"Enabled":enabled})}


func _key(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_D
	event.keycode = KEY_D
	event.pressed = pressed
	Input.parse_input_event(event)


func _settle() -> void:
	await physics_frame
	await physics_frame
	await physics_frame


func _capture(label: String) -> void:
	if not _rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/doors"))
	_check(root.get_texture().get_image().save_png("res://output/doors/"+label+".png")==OK,"Capture must save")


func _run() -> void:
	if _rendered:
		root.size = Vector2i(960,480)
		root.content_scale_size = Vector2i(320,160)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var stage: Node2D = Node2D.new()
	root.add_child(stage)
	var floor_art: Polygon2D = Polygon2D.new()
	floor_art.polygon = PackedVector2Array([Vector2.ZERO,Vector2(320,0),Vector2(320,160),Vector2(0,160)])
	floor_art.color = Color("#362030")
	floor_art.z_index = -20
	stage.add_child(floor_art)
	var values: Array = []
	values.resize(200)
	values.fill(0)
	for y: int in range(10):
		for x: int in range(20):
			if x in [0,19] or y in [0,9]:
				values[y*20+x] = 1
			elif x in [7,14]:
				values[y*20+x] = 3
	var trigger: Dictionary = {"__identifier":"GameplayTrigger","px":[24,48],"width":32,"height":32,"__pivot":[0,0],
		"fieldInstances":_fields({"ConditionId":"switch_a","ConditionValue":true,"Once":true,"Enabled":true})}
	var layers: Array = [
		{"__identifier":"Gameplay","__type":"IntGrid","__cWid":20,"__gridSize":16,"intGridCsv":values},
		{"__identifier":"GameplayAreas","__type":"Entities","__pxTotalOffsetX":8,"__pxTotalOffsetY":16,
			"entityInstances":[_control("west","switch_a",Vector2i(104,0)),
				_control("east","boss_dead",Vector2i(224,64),Vector2(0.5,0.5)),
				_control("east","key_found",Vector2i(224,64),Vector2(0.5,0.5)),
				_control("disabled","never",Vector2i(104,0),Vector2.ZERO,false),trigger]}]
	var gameplay: Node2D = GAMEPLAY.new() as Node2D
	gameplay.name = "Gameplay"
	stage.add_child(gameplay)
	gameplay.call("configure",layers)
	var player: Player = PLAYER.instantiate() as Player
	player.position = Vector2(72,76)
	player.arena_bounds = Rect2(0,0,320,160)
	player.movement_bounds = Rect2(4,4,312,152)
	player.dash_afterimages_enabled = false
	stage.add_child(player)
	var camera: Camera2D = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(160,80)
	stage.add_child(camera)
	camera.make_current()
	await _settle()
	_check(int(gameplay.call("get_door_cell_count"))==16,"All painted DoorBlock cells must be imported")
	_check(bool(gameplay.call("is_door_cell_locked",Vector2i(7,4))),"DoorBlock must start closed")
	_check((gameplay.get_node("DoorBlocks/Door_7_4") as Polygon2D).visible,"Closed door must be visible")
	await _capture("closed")
	_key(true)
	await create_timer(0.65).timeout
	_key(false)
	_check(player.position.x<110,"Closed door must stop walking")
	player.position = Vector2(72,76)
	player.reset_physics_interpolation()
	_check(player.try_dash(Vector2.RIGHT),"Dash must start for collision test")
	await create_timer(0.25).timeout
	_check(player.position.x<110,"Closed door must also stop a dash")
	player.position = Vector2(48,76)
	player.intro_locked = true
	player.reset_physics_interpolation()
	await _settle()
	_check(not bool(gameplay.call("is_condition_met","switch_a")),"Trigger must wait for startup control lock to end")
	player.intro_locked = false
	await _settle()
	_check(bool(gameplay.call("is_condition_met","switch_a")),"Entering the authored trigger must activate its condition")
	_check(not bool(gameplay.call("is_door_cell_locked",Vector2i(7,4))),"Matching door must open")
	_check(bool(gameplay.call("is_door_cell_locked",Vector2i(14,4))),"Other door must remain closed")
	_check(not (gameplay.get_node("DoorBlocks/Door_7_4") as Polygon2D).visible,"Open door visual must disappear")
	_key(true)
	await create_timer(1.2).timeout
	_key(false)
	_check(player.position.x>132,"Player must physically pass after the condition is met")
	gameplay.call("set_condition","boss_dead",true)
	await _settle()
	_check(bool(gameplay.call("is_door_cell_locked",Vector2i(14,4))),"Overlapping controls must require every condition")
	gameplay.call("set_condition","key_found",true)
	await _settle()
	_check(not bool(gameplay.call("is_door_cell_locked",Vector2i(14,4))),"Game event must release the second door when all conditions hold")
	await _capture("open")
	gameplay.call("set_condition","boss_dead",false)
	await _settle()
	_check(bool(gameplay.call("is_door_cell_locked",Vector2i(14,4))),"Resetting a condition must close its door")
	gameplay.call("set_door_region_locked",Rect2i(14,1,1,8),false)
	await _settle()
	_check(not bool(gameplay.call("is_door_cell_locked",Vector2i(14,4))),"MonsterShift region command must work")
	gameplay.call("set_door_locked","east",true)
	await _settle()
	_check(bool(gameplay.call("is_door_cell_locked",Vector2i(14,4))),"Named door command must work")
	gameplay.call("set_doors_locked",false)
	await _settle()
	_check(not bool(gameplay.call("is_door_cell_locked",Vector2i(14,4))),"Global door command must work")
	gameplay.call("set_condition","switch_a",false)
	player.position = Vector2(48,76)
	player.reset_physics_interpolation()
	await _settle()
	_check(not bool(gameplay.call("is_condition_met","switch_a")),"Once trigger must not activate again after leaving and returning")
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"ok":_failures.is_empty(),"rendered":_rendered,"failures":_failures}))
	quit(0 if _failures.is_empty() else 1)
