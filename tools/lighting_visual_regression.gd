extends SceneTree
## Rendered captures and logic assertions against the actual production scenes.
var failures: int = 0
var rendered: bool = false

func _initialize() -> void:
	rendered = DisplayServer.get_name() != "headless"
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func capture(label: String) -> void:
	if not rendered:
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://renders/" + label + ".png")

func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	var arena: Node2D = current_scene as Node2D
	var boss: Node2D = arena.get_node("MinotaurChair") as Node2D
	var encounter: Node = boss.get_node("TutorialEncounter")
	var completion: Node = encounter.get("completion") as Node
	completion.set_meta(&"elite_explained", true)
	boss.set("auto_start_encounter", false)
	await create_timer(2.7).timeout
	var rig: Node2D = arena.get_node("ArenaLightingRig") as Node2D
	var tutorial_style: Node2D = arena.get_node("ProjectileWorldStyle") as Node2D
	var shared_profile: Resource = tutorial_style.get("profile") as Resource
	check(rig.get_child_count() == 8, "Tutorial rig must contain ambient modulation and seven soft lights only")
	check(not rig.has_node("CenterLight"), "Tutorial still has the broad central light")
	var crater_lights: Array = rig.get("crater_lights")
	check(crater_lights.size() == 2, "Both tutorial craters must have their own light")
	if crater_lights.size() == 2:
		var large_light: PointLight2D = crater_lights[0] as PointLight2D
		var small_light: PointLight2D = crater_lights[1] as PointLight2D
		check(large_light.position == Vector2(-176, -80), "Large crater light is not centered on the actual hole")
		check(small_light.position == Vector2(144, 8), "Small crater light is not centered on the actual hole")
		check(large_light.scale * 64.0 == Vector2(88, 72), "Large crater light does not fit the hole")
		check(small_light.scale * 64.0 == Vector2(56, 48), "Small crater light does not fit the hole")
	for child: Node in rig.get_children():
		check(not child is Polygon2D, "Explicit light beam is still present in the tutorial")
	check((arena.get_node("FarClouds/CloudField") as Sprite2D).material != null, "Cloud depth layer was not protected from ambient dimming")
	var player: Player = arena.get_node("Mox") as Player
	var player_bar: Range = completion.get_node("Nox/HP") as Range
	check(player_bar.size == Vector2(68, 10) and player_bar.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Player HUD must stay compact without smoothing")
	var gameplay_camera: Camera2D = player.get_node("Camera2D") as Camera2D
	gameplay_camera.enabled = false
	var overview: Camera2D = Camera2D.new()
	overview.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	overview.position = Vector2(0, -35)
	overview.zoom = Vector2.ONE * 0.43
	arena.add_child(overview)
	overview.make_current()
	await capture("tutorial_iluminacao_intro")
	encounter.call(&"skip_to_boss")
	player.contact_invulnerability = 100.0
	await create_timer(1.5).timeout
	# Both spell signals and actual encounter phase drive the rig.
	rig.call(&"_on_departure")
	check(is_zero_approx(float(rig.get("boss_weight"))), "Asterion light lingered after launch")
	rig.call(&"_on_target_locked", Vector2(30, -40))
	check(bool(rig.get("locked_target")), "Skybreaker target lighting did not lock")
	rig.call(&"_on_impact", Vector2(30, -40))
	check(float(rig.get("impact_remaining")) > 0.0, "Skybreaker impact did not flash")
	var landing_wait: float = 0.0
	while int(boss.get("state")) != 12 and landing_wait < 8.0:
		await process_frame
		landing_wait += root.get_process_delta_time()
	check(landing_wait < 8.0, "Asterion did not finish the real Skybreaker")
	boss.set_physics_process(false)
	var actor: CharacterBody2D = boss.get("actor") as CharacterBody2D
	check(actor.visible, "Captured boss is still offscreen")
	player.position = Vector2(-40, 35)
	player.reset_physics_interpolation()
	actor.global_position = Vector2(50, -35)
	actor.reset_physics_interpolation()
	check(int(encounter.get("phase")) == 7, "Boss battle did not start")
	check((completion.get_node("Boss") as Control).visible, "New boss bar stayed hidden in combat")
	var bar: Range = completion.get_node("Boss/HP") as Range
	var boss_name: Label = completion.get_node("Boss/Name") as Label
	check(bar.size == Vector2(260, 29), "Boss life bar was not reduced by approximately ten percent")
	check(boss_name.text == "Asterion" and boss_name.get_global_rect().end.y <= bar.get_global_rect().position.y, "Asterion name is not above the life bar")
	check(boss_name.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and is_equal_approx(boss_name.get_global_rect().get_center().x, bar.get_global_rect().get_center().x), "Asterion name is not centered over its frame")
	check(bar.max_value == 270.0 and bar.value == float(boss.get("health")), "Boss bar does not track real health")
	boss.call(&"take_damage", 90.0)
	check(bar.value == 180.0, "Boss damage did not update the new bar")
	await create_timer(0.75).timeout
	check(is_equal_approx(float(bar.get("damage_ratio")), 2.0 / 3.0), "Damage trail did not settle to health")
	await capture("tutorial_iluminacao_atual")
	overview.enabled = false
	gameplay_camera.enabled = true
	gameplay_camera.make_current()
	await create_timer(0.15).timeout
	var tutorial_weapon: Node2D = player.get_node("BoosterShooter") as Node2D
	var tutorial_reticle: Sprite2D = encounter.get("reticle") as Sprite2D
	tutorial_reticle.position = Vector2(340, 175)
	await process_frame
	await process_frame
	var tutorial_shot: Node2D = tutorial_weapon.call(&"fire_once") as Node2D
	check(is_instance_valid(tutorial_shot) and tutorial_shot.has_meta(&"world_styled"), "Tutorial shot did not receive the shared weapon presentation")
	if is_instance_valid(tutorial_shot):
		check(tutorial_shot.get_node("WorldPresentation").get_child_count() == 1, "Tutorial shot has ghost copies")
	check(float(tutorial_style.get("shot_light").energy) > 0.0, "Tutorial weapon did not emit its shared soft shot light")
	await create_timer(0.05).timeout
	await capture("tutorial_boss_atual")
	change_scene_to_file("res://scenes/dungeon/merchant_platform.tscn")
	await create_timer(0.65).timeout
	var room: Node2D = current_scene as Node2D
	var controller: Node2D = room.get_node("ManifestationController") as Node2D
	var style: Node2D = room.get_node("ProjectileWorldStyle") as Node2D
	check(style.get("profile") == shared_profile, "Tutorial and training are not using the same visual profile")
	check(style.get("impact_lights").size() == 3, "Impact light pool is not bounded to three")
	var aim: Sprite2D = room.get_node("CombatUI/Crosshair") as Sprite2D
	aim.position = Vector2(370, 95)
	controller.call(&"_fire")
	check(float(style.get("shot_light").energy) > 0.0, "Training weapon did not emit its shared soft shot light")
	check(is_equal_approx(float(room.get_node("Nox/BoosterShooter").get("shot_recoil")), float(shared_profile.get("shot_recoil"))), "Training recoil differs from the shared tutorial base")
	await create_timer(0.16).timeout
	var shots: Array[Node] = get_nodes_in_group(&"manifestation_projectiles")
	check(not shots.is_empty() and shots[0].has_meta(&"world_styled"), "Training projectile did not receive its presentation")
	if not shots.is_empty():
		var shot_presentation: Node = shots[0].get_node("WorldPresentation")
		check(shot_presentation.get_child_count() == 1, "Projectile presentation duplicated the original shot")
	await capture("treinamento_slime_atual")
	for code_index: int in [1, 2, 3, 4, 5, 6, 7]:
		controller.set("selected_index", code_index)
		controller.call(&"_equip_selected")
		controller.call(&"_update_hud")
		var press: InputEventMouseButton = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = aim.position * Vector2(root.size) / Vector2(root.content_scale_size)
		Input.parse_input_event(press)
		await create_timer(0.36).timeout
		await capture("treinamento_manifestacao_%d" % code_index)
		press.pressed = false
		Input.parse_input_event(press)
		await create_timer(0.5).timeout
	style.call(&"flash_impact", Vector2(50, -10), &"M07")
	check(float(style.get("timers")[0]) >= 0.0, "Impact pool timer invalid")
	await create_timer(0.25).timeout
	for light: PointLight2D in style.get("impact_lights"):
		check(is_zero_approx(light.energy), "Impact light did not expire")
	check(is_zero_approx(float(style.get("shot_light").energy)), "Weapon pulse did not expire")
	print("LIGHTING / BOSS BAR / TRAINING PRESENTATION: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
