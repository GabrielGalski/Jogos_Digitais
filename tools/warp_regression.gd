extends SceneTree
## Startup choreography and actual cross-file travel, invalid routes and arrival rearming.
const WARPS: Script = preload("res://scripts/dungeon/ldtk_warps.gd")
var _failures: Array[String] = []
var _rendered: bool = false


func _initialize() -> void:
	_rendered = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _wait_entry(arena: Node2D) -> void:
	var deadline: int = Time.get_ticks_msec()+4000
	while is_instance_valid(arena) and not bool(arena.get("entry_complete")) and Time.get_ticks_msec()<deadline:
		await process_frame
	_check(is_instance_valid(arena) and bool(arena.get("entry_complete")),"Arrival must complete and release control")


func _capture(label: String) -> void:
	if not _rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/warp"))
	_check(root.get_texture().get_image().save_png("res://output/warp/"+label+".png")==OK,"Capture must save")


func _set_field(entity: Dictionary, field_name: String, value: Variant) -> void:
	for field: Dictionary in entity.fieldInstances:
		if str(field.__identifier)==field_name:
			field["__value"] = value


func _write(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check_flat_warp(arena: Node2D, player: Player) -> void:
	var gate: Node2D = (arena.get_node("Warps").get("gates") as Array)[0] as Node2D
	var config: Dictionary = gate.get("data")
	var original_target: String = str(config.TargetLevel)
	config["TargetLevel"] = ""
	var original_position: Vector2 = player.position
	var plate: Sprite2D = gate.get_node("Plate") as Sprite2D
	_check(plate.texture.get_size()==Vector2(48,48),"Resized 48x48 sprite must load without cropping")
	_check(plate.position==Vector2(-24,-24) and plate.scale==Vector2.ONE,"Square warp must use its native size and center anchor")
	_check(bool(gate.call("supports_feet",player.to_global(Vector2(0,3)))),"Arrival must stand inside the new sprite")
	_check(player.floor_height==0 and player.body.position.y==0,"Arrival must stay at ground level")
	_check((player.get_node("BoosterShooter") as Node2D).position.y==0,"Weapon must stay at ground level")
	var shadow: Node2D = player.get_node("RoomContactShadow") as Node2D
	_check(shadow.position.y==7,"Contact shadow must retain its normal ground offset")
	var corners: Array[Vector2] = [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]
	for corner: Vector2 in corners:
		player.position = original_position
		player.reset_physics_interpolation()
		var horizontal: Key = KEY_A if corner.x<0 else KEY_D
		var vertical: Key = KEY_W if corner.y<0 else KEY_S
		_key(horizontal,true)
		_key(vertical,true)
		var stayed_flat: bool = true
		for tick: int in range(24):
			await physics_frame
			stayed_flat = stayed_flat and player.floor_height==0 and player.body.position.y==0
		_key(horizontal,false)
		_key(vertical,false)
		_check(stayed_flat,"Walking toward all four corners must not raise the character")
		_check(player.position.distance_to(original_position)>20,"The flat warp must remain walkable")
	player.position = original_position
	player.reset_physics_interpolation()
	await _capture("flat_platform")
	config["TargetLevel"] = original_target


func _run() -> void:
	if _rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
	var packed: PackedScene = load("res://scenes/dungeon/ldtk_arena.tscn") as PackedScene
	var arena: Node2D = packed.instantiate() as Node2D
	root.add_child(arena)
	current_scene = arena
	var player: Player = arena.get_node("Nox") as Player
	_check(player.intro_locked and not bool(arena.get("entry_complete")),"Startup must lock movement for the warp arrival")
	_check(arena.has_node("Warps") and arena.has_node("WarpTransition"),"Main scene must build warp and cutscene")
	var gameplay: Node2D = arena.get_node("Gameplay") as Node2D
	_check(player.position.is_equal_approx(gameplay.get("start_position") as Vector2),"Entrance placement must retain authored Start")
	var health: float = player.health
	player.receive_skybreaker_hit(3)
	_check(player.health == health,"Arrival must protect the player during the visual lock")
	await create_timer(float(arena.get("warp_arrival_duration"))*0.45).timeout
	await _capture("arrival_beam")
	await _wait_entry(arena)
	_check(not player.intro_locked and player.body.material == null,"Arrival must restore sprite material and controls")
	await _capture("arrival_complete")
	await _check_flat_warp(arena,player)
	arena.queue_free()
	await process_frame
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var source: Dictionary = {}
	for level: Dictionary in WARPS.levels(data):
		if str(level.identifier)=="Room_1":
			source=level.duplicate(true)
	var destination: Dictionary = source.duplicate(true)
	source["identifier"]="Warp_A"
	destination["identifier"]="Warp_B"
	for layer: Dictionary in source.layerInstances:
		for entity: Dictionary in layer.entityInstances:
			if str(entity.__identifier)=="Warp":
				_set_field(entity,"TargetLevel","Warp_B")
				_set_field(entity,"TargetMap","warp_destination_fixture.ldtk")
	for layer: Dictionary in destination.layerInstances:
		for entity: Dictionary in layer.entityInstances:
			if str(entity.__identifier)=="Warp":
				_set_field(entity,"TargetLevel","Warp_A")
				_set_field(entity,"TargetMap","warp_source_fixture.ldtk")
	var source_data: Dictionary = data.duplicate(true)
	source_data["levels"]=[source]
	var target_data: Dictionary = data.duplicate(true)
	target_data["levels"]=[destination]
	_write("res://tmp/warp_source_fixture.ldtk",source_data)
	_write("res://tmp/warp_destination_fixture.ldtk",target_data)
	var config: Dictionary = WARPS.descriptions(source.layerInstances)[0]
	_check(bool(WARPS.resolve("res://tmp/warp_source_fixture.ldtk",config).get("ok")),"Relative cross-file route must validate")
	var bad: Dictionary = config.duplicate()
	bad["TargetMap"]="res://../outside.ldtk"
	_check(not bool(WARPS.resolve("res://tmp/warp_source_fixture.ldtk",bad).get("ok")),"Routes must remain inside the project")
	bad=config.duplicate()
	bad["TargetWarp"]="missing"
	_check(not bool(WARPS.resolve("res://tmp/warp_source_fixture.ldtk",bad).get("ok")),"Missing destination warp must be rejected")
	var unsafe_data: Dictionary = target_data.duplicate(true)
	for layer: Dictionary in unsafe_data.levels[0].layerInstances:
		if str(layer.__identifier)=="Gameplay":
			for index: int in range((layer.intGridCsv as Array).size()):
				if int(layer.intGridCsv[index])==4:
					layer.intGridCsv[index]=2
	_write("res://tmp/warp_destination_fixture.ldtk",unsafe_data)
	_check(not bool(WARPS.resolve("res://tmp/warp_source_fixture.ldtk",config).get("ok")),"A destination over a gameplay gap must be rejected")
	_write("res://tmp/warp_destination_fixture.ldtk",target_data)
	arena=packed.instantiate() as Node2D
	arena.set("map_path","res://tmp/warp_source_fixture.ldtk")
	arena.set("level_name","Warp_A")
	root.add_child(arena)
	current_scene=arena
	await _wait_entry(arena)
	player=arena.get_node("Nox") as Player
	player.health=42
	var runtime: RefCounted = player.get_node("BoosterShooter").get("card_runtime") as RefCounted
	var spawn: Vector2 = player.position
	player.position+=Vector2(0,128)
	player.reset_physics_interpolation()
	await physics_frame
	await physics_frame
	player.position=spawn
	player.reset_physics_interpolation()
	await physics_frame
	await process_frame
	_check(bool(arena.get("_travel_busy")),"Walking off and back onto a linked warp must start departure")
	await create_timer(float(arena.get("warp_departure_duration"))*0.45).timeout
	await _capture("departure_beam")
	var deadline: int = Time.get_ticks_msec()+4000
	while is_instance_valid(arena) and Time.get_ticks_msec()<deadline:
		await process_frame
	var next_room: Node2D = current_scene as Node2D
	_check(next_room != null and str(next_room.get("level_name"))=="Warp_B","Departure must load the other map and room")
	await _wait_entry(next_room)
	player=next_room.get_node("Nox") as Player
	_check(player.health==42 and player.get_node("BoosterShooter").get("card_runtime")==runtime,"Travel must retain health and equipped card runtime")
	await create_timer(0.35).timeout
	_check(current_scene==next_room and not player.intro_locked,"Arrival must not bounce immediately to the previous room")
	await _capture("destination_arrival")
	var gate: Node2D = (next_room.get_node("Warps").get("gates") as Array)[0] as Node2D
	var gate_data: Dictionary = gate.get("data")
	gate_data["TargetLevel"]="MissingRoom"
	player.position+=Vector2(0,128)
	await physics_frame
	await physics_frame
	player.position=spawn
	await physics_frame
	await process_frame
	_check(not str(next_room.get("last_warp_error")).is_empty() and not player.intro_locked,"Invalid destination must leave player in the current room with controls")
	next_room.queue_free()
	await process_frame
	print(JSON.stringify({"ok":_failures.is_empty(),"rendered":_rendered,"failures":_failures}))
	quit(0 if _failures.is_empty() else 1)
