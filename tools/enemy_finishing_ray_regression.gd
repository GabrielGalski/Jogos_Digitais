extends SceneTree
## Fatal-only violet cut, real weapon kills, area damage, boss and visual layering.

const MINION: PackedScene = preload("res://scenes/enemies/minotaur.tscn")
const RAY: Script = preload("res://scripts/combat/effects/enemy_finishing_ray.gd")
const BOSS: Script = preload("res://scripts/asterion_skybreaker.gd")
var checks: int = 0
var failures: int = 0
var player: Player
var boss: Node2D
var camera: Camera2D
var effects: CombatEffects


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("[FINISHING RAY] " + message)


func _run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	boss = current_scene.get_node("MinotaurChair") as Node2D
	boss.set("auto_start_encounter", false)
	await create_timer(3.8).timeout
	player = current_scene.get_node("Mox") as Player
	player.intro_locked = false
	player.position = Vector2(0, 80)
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player.set_physics_process(false)
	camera = player.get_node("Camera2D") as Camera2D
	await physics_frame
	camera.reset_smoothing()
	camera.force_update_scroll()
	var kit: Node2D = player.get_node("GameplayKit") as Node2D
	kit.call("set_combat_enabled", true)
	kit.set_process(false)
	effects = kit.get("effects") as CombatEffects
	var gun: Node2D = player.get_node("BoosterShooter") as Node2D
	gun.set_process(false)
	var enemy: Minotaur = _spawn(Vector2(60, 80))
	await create_timer(0.4).timeout
	enemy.take_damage(3.0)
	check(_rays().is_empty() and enemy.is_alive(), "no ray on ordinary hit")
	await create_timer(0.13).timeout
	var previous_material: Material = enemy.sprite.material
	var camera_zoom: Vector2 = camera.zoom
	var camera_offset: Vector2 = camera.offset
	enemy.take_damage(9.0)
	check(_rays().size() == 1 and not enemy.is_alive(), "one ray at actual minion death")
	var ray: Node2D = _rays()[0] as Node2D
	var core: Sprite2D = ray.get("core") as Sprite2D
	var glow: Sprite2D = ray.get("glow") as Sprite2D
	var light: PointLight2D = ray.get("light") as PointLight2D
	check(core.texture.resource_path == "res://assets/effects/finisher/effect.png" and core.modulate == Color.WHITE and is_zero_approx(core.rotation), "authored finisher, original palette and diagonal")
	check(glow.modulate.is_equal_approx(Color(Color("#8157c6"), 0.65)) and light.color == Color("#8157c6"), "same violet in glow and local light")
	check(ray.z_index < enemy.z_index + enemy.sprite.z_index and not ray.z_as_relative, "ray behind white sprite")
	check(ray.get_parent() == current_scene, "local world effect, not HUD flash")
	check(enemy.sprite.material != previous_material and float((enemy.sprite.material as ShaderMaterial).get_shader_parameter(&"flash_amount")) == 1.0, "white death pose synchronized")
	enemy.take_damage(99.0)
	check(RAY.play(enemy, enemy.sprite) == null and _rays().size() == 1, "one effect only despite repeated lethal contacts")
	check(not light.shadow_enabled and ray.get_child_count() == 3, "only cut, glow and light, no physics")
	if DisplayServer.get_name() != "headless":
		await _capture("finishing_ray_minion", ray)
	await create_timer(0.025).timeout
	check(core.scale.x > float(ray.get("sprite_scale")) * 0.95, "fast reveal reaches full authored sprite")
	await create_timer(0.16).timeout
	check(_rays().is_empty() and not is_instance_valid(enemy), "ray and minion clean up automatically")
	check(camera.zoom == camera_zoom and camera.offset == camera_offset and is_equal_approx(Engine.time_scale, 1.0), "no camera or timescale change")
	# A real M01 shot must use the same fatal event, regardless of its damage source.
	enemy = _spawn(Vector2(60, 80))
	await create_timer(0.4).timeout
	enemy.resistance = 3.0
	gun.set("cooldown", 0.0)
	gun.set("aim_screen_override", root.get_canvas_transform() * enemy.global_position)
	var shot: Node2D = gun.call("fire_once") as Node2D
	check(shot != null, "real M01 shot emitted")
	await create_timer(0.095).timeout
	check(not is_instance_valid(enemy) or not enemy.is_alive(), "real projectile kills target")
	check(_rays().size() == 1, "real projectile death creates exactly one cut")
	await create_timer(0.3).timeout
	# Multi-kill through the equipped Infusion gives one independent local cut per mob.
	var a: Minotaur = _spawn(Vector2(75, 120))
	var b: Minotaur = _spawn(Vector2(86, 120))
	await create_timer(0.4).timeout
	a.resistance = 3.0
	b.resistance = 2.0
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var attack: CardAttack = runtime.create_attack()
	attack.apply_primary_hit(a, a.global_position, Vector2.RIGHT, effects)
	check(not a.is_alive() and not b.is_alive() and _rays().size() == 2, "infusion multi-kill: one cut per enemy")
	await create_timer(0.2).timeout
	# Boss uses its displaced foot anchor and keeps its defeat animation after the flash.
	var actor: Node2D = boss.get_node("Actor") as Node2D
	actor.global_position = Vector2(90, 80)
	actor.show()
	boss.set("state", BOSS.State.CHASE)
	boss.set("health", 3.0)
	boss.set_physics_process(false)
	var visual: Sprite2D = actor.get_node("Visual") as Sprite2D
	var boss_material: Material = visual.material
	boss.call("take_damage", 3.0)
	check(_rays().size() == 1 and int(boss.get("state")) == BOSS.State.DEFEATED, "boss finishing cut wired")
	ray = _rays()[0] as Node2D
	check(ray.z_index < actor.z_index and visual.material != boss_material, "boss ray below white defeat pose")
	check(ray.global_position.distance_to(visual.to_global(ray.get("local_center") as Vector2)) < 0.01, "boss ray follows the actual sprite anchor")
	if DisplayServer.get_name() != "headless":
		await _capture("finishing_ray_asterion", ray)
	await create_timer(0.025).timeout
	await create_timer(0.16).timeout
	check(_rays().is_empty() and visual.material == boss_material and visual.visible, "boss original material and defeat pose restored")
	check(RAY.play(boss, visual) == null, "boss cut never repeats")
	print("ENEMY_FINISHING_RAY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _spawn(point: Vector2) -> Minotaur:
	var enemy: Minotaur = MINION.instantiate() as Minotaur
	enemy.position = point
	current_scene.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _rays() -> Array[Node]:
	return get_nodes_in_group(&"enemy_finishing_rays")


func _capture(label: String, ray: Node2D) -> void:
	# Hold the exact peak for QA; a hidden native window can render too late for a 0.14s FX.
	var was_paused: bool = paused
	var previous_elapsed: float = float(ray.get("elapsed"))
	paused = true
	ray.set("elapsed", 0.025)
	ray.call("_update_visual")
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image.save_png("res://tmp/%s.png" % label) == OK, "capture %s" % label)
	ray.set("elapsed", previous_elapsed)
	ray.call("_update_visual")
	paused = was_paused
