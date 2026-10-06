extends SceneTree

var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/dungeon/merchant_platform.tscn")
	await create_timer(0.6).timeout
	var controller: Node = current_scene.get_node("ManifestationController")
	controller.set_physics_process(false)
	controller.set("selected_index", 5)
	controller.call("_equip_selected")
	var channel: Node = controller.get("banshee") as Node
	var hud: ColorRect = channel.get("hud") as ColorRect
	var player: Player = current_scene.get_node("Nox") as Player
	check(hud.size.is_equal_approx(Vector2(24, 1)) and hud.get_child_count() == 1 and hud.get_child(0) is ColorRect, "M03 heat indicator is not a single short text-free line")
	channel.call("_process", 0.0)
	check(hud.position.y > player.get_global_transform_with_canvas().origin.y, "M03 bar is not below Nox")
	channel.call("tick", 1.0, true, true)
	check(is_equal_approx(float(channel.get("heat")), 25.0), "heat must rise while held")
	check(is_equal_approx((hud.get_node("Fill") as ColorRect).size.x, 6.0), "single-line fill did not reflect 25% heat")
	var visual: Node2D = channel.get("visual") as Node2D
	check(is_instance_valid(visual) and bool(channel.get("active")), "continuous visual absent")
	channel.call("tick", 0.1, true, true)
	check(channel.get("visual") == visual, "holding creates duplicate cones")
	var muzzle: Marker2D = current_scene.get_node("Nox/BoosterShooter/WeaponPivot/Muzzle") as Marker2D
	muzzle.global_position += Vector2(20, 10)
	visual.call("follow_source")
	check(visual.global_position.is_equal_approx(muzzle.global_position), "cone does not track shooter")
	var reticle: Node2D = current_scene.get_node("CombatUI/Crosshair") as Node2D
	reticle.position = root.get_canvas_transform() * (muzzle.global_position + Vector2.UP * 100.0)
	visual.call("follow_source")
	check(Vector2.RIGHT.rotated(visual.rotation).dot(Vector2.UP) > 0.99, "held cone does not turn toward cursor")
	var before: float = float(channel.get("heat"))
	channel.call("tick", 0.1, false, true)
	check(is_equal_approx(float(channel.get("heat")), before - 5.0), "release must cool immediately")
	check(not bool(channel.get("active")) and channel.get("visual") == null, "release leaves cone active")
	var prior_cooldown: float = float(channel.get("hit_cooldown"))
	channel.call("tick", 0.0, true, true)
	check(is_equal_approx(float(channel.get("hit_cooldown")), prior_cooldown), "clicking resets hit clock")
	channel.call("tick", 4.0, true, true)
	check(is_equal_approx(float(channel.get("heat")), 100.0) and bool(channel.get("overheated")), "missing overheat")
	check(not bool(channel.get("active")), "overheated weapon still fires")
	channel.call("tick", 0.6, false, true)
	check(is_equal_approx(float(channel.get("heat")), 100.0), "overheat delay skipped on release")
	channel.call("tick", 0.6, true, true)
	check(is_equal_approx(float(channel.get("heat")), 100.0), "overheat delay shortened")
	channel.call("tick", 0.5, true, true)
	check(is_equal_approx(float(channel.get("heat")), 75.0) and not bool(channel.get("active")), "overheat cooling not locked")
	channel.call("tick", 1.5, true, true)
	check(is_zero_approx(float(channel.get("heat"))) and not bool(channel.get("overheated")), "not recovered at zero")
	channel.call("tick", 1.0, true, true)
	channel.call("tick", 0.1, false, false)
	check(is_equal_approx(float(channel.get("heat")), 20.0), "switching weapon resets heat")
	check((channel.get("hud") as Control).visible, "residual heat indicator hidden")
	print("BANSHEE HEAT: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
