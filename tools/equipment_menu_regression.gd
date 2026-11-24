extends SceneTree
## Shared equipment GUI, firing and loadout transfer across all four scenes.

const SCENES: Array[String] = ["res://scenes/maps/open_world.tscn", "res://scenes/dungeon/ldtk_arena.tscn",
	"res://scenes/tutorial_arena.tscn", "res://scenes/bosses/elemental_golem_arena.tscn"]
var checks: int = 0
var failures: int = 0
var scene: Node
var actor: Player
var gun: Node2D
var controller: Node


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("EQUIPMENT: " + message)


func key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func click(button: Button) -> void:
	var center: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = center
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = center
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/cards/equipment/" + name + ".png")


func _menu_contract(first_scene: bool) -> void:
	var previous: StringName = (controller.call("selected_model") as ProceduralManifestationModel).code()
	var health: float = actor.health
	var at: Vector2 = actor.position
	await key(KEY_I)
	await process_frame
	var menu: CanvasLayer = scene.get_node_or_null("EquipmentMenu") as CanvasLayer
	check(menu != null and paused, "Equipment menu pauses " + scene.scene_file_path)
	if menu == null:
		return
	check((controller.call("selected_model") as ProceduralManifestationModel).code() == previous, "Opening does not cycle the equipped weapon")
	var slots: HBoxContainer = menu.get("_slots") as HBoxContainer
	check(slots.get_child_count() == 3 and not (slots.get_child(1) as Button).disabled and not (slots.get_child(2) as Button).disabled, "All three card slots are enabled")
	if first_scene:
		await create_timer(0.25).timeout
		await capture("01_slots")
	await click(menu.get("manifestation_slot") as Button)
	await create_timer(0.4).timeout
	var choices: Dictionary = menu.get("model_buttons") as Dictionary
	check(choices.size() == 8, "All eight models fit in the manifestation picker")
	if first_scene:
		await capture("02_cards")
	await click(choices[1] as Button)
	check((controller.call("selected_model") as ProceduralManifestationModel).code() == &"M02", "Clicking Massa de Slime equips its existing model")
	check((choices[1] as Button).button_pressed, "The selected card remains visibly selected")
	await click(choices[6] as Button)
	check((controller.call("selected_model") as ProceduralManifestationModel).code() == &"M05", "The Basilisk card equips its new projectile model")
	await click(choices[5] as Button)
	var dragon: ProceduralManifestationModel = controller.call("selected_model") as ProceduralManifestationModel
	check(dragon.code() == &"M08" and dragon.card.display_name == "Garganta de Dragão", "The Dragon Throat card equips its channel")
	menu.call("show_aspect", 1)
	await process_frame
	choices = menu.get("model_buttons") as Dictionary
	check(choices.size() == 8, "All eight infusions are available")
	await click(choices[2] as Button)
	check((gun.get("card_runtime") as CardCombatRuntime).copy_loadout().infusion.card_id == &"CARD_INF_003", "Infusion selector equips Odopi")
	menu.call("show_aspect", 2)
	await process_frame
	choices = menu.get("model_buttons") as Dictionary
	check(choices.size() == 8, "All eight mutations are available")
	await click(choices[3] as Button)
	check((gun.get("card_runtime") as CardCombatRuntime).copy_loadout().mutation.card_id == &"CARD_MUT_004", "Mutation selector equips Mandrake")
	check(actor.position == at and actor.health == health, "Simulation stays paused during selection")
	await key(KEY_I)
	await process_frame
	check(not paused and scene.get_node_or_null("EquipmentMenu") == null, "I closes the screen and resumes the same scene")
	check(bool(gun.get("require_mouse_release")) or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "Closing cannot automatically fire from the card click")


func _firing_contract(first_scene: bool) -> void:
	var models: Array[ProceduralManifestationModel] = controller.call("available_models") as Array[ProceduralManifestationModel]
	for index: int in models.size():
		controller.call("select_model", index)
		var model: ProceduralManifestationModel = models[index]
		var flash: Sprite2D = gun.get("_effect") as Sprite2D
		if model.family == ProceduralManifestationModel.Family.PROJECTILE:
			var shot: Node2D = gun.call("fire_once") as Node2D
			check(shot != null, "Projectile uses shared executor " + String(model.code()))
			check(flash.visible and flash.modulate.is_equal_approx(model.body_color), "Original muzzle animation uses projectile color " + String(model.code()))
			if first_scene:
				await capture("shot_" + String(model.code()))
			var frames: Dictionary = {}
			for step: int in 6:
				frames[flash.texture] = true
				await process_frame
			check(frames.size() >= 3, "Original multi-frame shot animation advances " + String(model.code()))
		else:
			gun.set_process(false)
			controller.call("set_trigger", true)
			await create_timer(0.15).timeout
			check(is_instance_valid(controller.get("channel")), "Continuous model creates a channel " + String(model.code()))
			check(not flash.visible, "Continuous model has no discrete muzzle burst " + String(model.code()))
			controller.call("open_equipment_menu")
			await process_frame
			check(paused and controller.get("channel") == null, "Opening the menu ends the active channel")
			await key(KEY_BACKSPACE)
			await process_frame
			gun.set_process(true)
			check(not paused and controller.get("channel") == null, "Closing does not restart an old channel")
	controller.call("select_model", 5)


func _run() -> void:
	Engine.max_fps = 60
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	for index: int in SCENES.size():
		if index == 0:
			change_scene_to_file(SCENES[index])
		else:
			check(bool(root.get_node("SceneJumper").call("travel_to_scene", scene, SCENES[index], actor)), "Shared scene transfer accepts the equipped card")
		await process_frame
		await process_frame
		scene = current_scene
		if scene == null:
			check(false, "Scene loaded")
			quit(1)
			return
		var entry: String = "entrance_complete" if index == 2 else "entry_complete"
		var elapsed: int = 0
		while not bool(scene.get(entry)) and elapsed < 600:
			await process_frame
			elapsed += 1
		actor = scene.get_node_or_null("Mox" if index == 2 else "Nox") as Player
		check(actor != null and bool(scene.get(entry)), "Scene arrival completed " + SCENES[index])
		if actor == null:
			quit(1)
			return
		gun = actor.get_node("BoosterShooter") as Node2D
		controller = actor.get_node_or_null("GameplayKit/Manifestations")
		check(controller != null and gun.get("manifestation_driver") == controller, "Scene uses the unified driver " + SCENES[index])
		actor.set_physics_process(false)
		actor.intro_locked = false
		actor.contact_invulnerability = 1000.0
		actor.get_node("GameplayKit").call("set_combat_enabled", true)
		if index > 0:
			check((controller.call("selected_model") as ProceduralManifestationModel).code() == &"M08", "Selection survives arrival in " + SCENES[index])
			var loadout: CardLoadout = (gun.get("card_runtime") as CardCombatRuntime).copy_loadout()
			check(loadout.infusion.card_id == &"CARD_INF_003" and loadout.mutation.card_id == &"CARD_MUT_004", "All three cards survive scene transfer")
		await _menu_contract(index == 0)
		await _firing_contract(index == 0)
	print("EQUIPMENT REGRESSION: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	quit(0 if failures == 0 else 1)
