extends SceneTree
## Exercises every authored frame, fractional health, rapid hits and the real HUD.
const BAR: PackedScene = preload("res://scenes/ui/player_life_bar.tscn")
const BAR_SCRIPT: Script = preload("res://scripts/ui/player_life_bar.gd")
var failures: int = 0
var rendered: bool = false

class DamageTarget extends Node2D:
	var health: float = 100.0
	var last_hit_direction: Vector2 = Vector2.RIGHT
	func is_alive() -> bool:
		return health > 0.0
	func take_damage(amount: float) -> void:
		health -= amount

func _initialize() -> void:
	rendered = DisplayServer.get_name() != "headless"
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func capture(label: String) -> Image:
	if not rendered:
		return null
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Image = root.get_texture().get_image()
	result.save_png("res://renders/" + label + ".png")
	return result

func at_sprite_pixel(image_data: Image, x: int, y: int) -> Color:
	# Sprite art is cropped at (14,3), displayed at 1x, then viewport-scaled 2x.
	return image_data.get_pixel(24 + (x - 14) * 2 + 1, 16 + (y - 3) * 2 + 1)

func _run() -> void:
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(480, 270)
	var layer: CanvasLayer = CanvasLayer.new()
	root.add_child(layer)
	var bar: Range = BAR.instantiate() as Range
	layer.add_child(bar)
	bar.position = Vector2(12, 8)
	bar.set_process(false)
	check(bar.get_script() == BAR_SCRIPT, "Bar scene has no sprite presentation script")
	check(bar.size == Vector2(68, 10), "Player bar is not half its previous width and height")
	check(bar.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Player bar must preserve sharp pixels without smoothing")
	check(int(bar.get("lit_blocks")) == 6 and int(bar.get("flash_mask")) == 0, "Initial full health incorrectly flashed")
	var full: Image = await capture("vida_personagem_cheia")
	if full != null:
		check(at_sprite_pixel(full, 75, 7).is_equal_approx(Color("#2cf7a3")), "Rendered player health color differs from #2cf7a3")
	bar.value = 57.0
	check(int(bar.get("lit_blocks")) == 6 and int(bar.get("flash_mask")) == 0, "Partial-block damage falsely crossed a threshold")
	var partial: Image = await capture("vida_personagem_parcial")
	if partial != null:
		check(at_sprite_pixel(partial, 75, 7).is_equal_approx(Color("#2cf7a3")), "Partial block lost retained green pixels")
		check(not at_sprite_pixel(partial, 79, 7).is_equal_approx(Color("#2cf7a3")), "Partial-block damage was not visible")
	for remaining: int in [5, 4, 3, 2, 1, 0]:
		bar.value = remaining * 10.0
		check(int(bar.get("lit_blocks")) == remaining, "Incorrect sprite mapping for %d blocks" % remaining)
		check(int(bar.get("flash_mask")) == (1 << remaining), "Incorrect red frame mapping for %d blocks" % remaining)
		check(bool(bar.get("flash_visible")), "Threshold did not begin with a red pulse")
		var red: Image = await capture("vida_personagem_pisca_%d" % remaining)
		if red != null:
			var center_x: int = int(BAR_SCRIPT.BLOCK_STARTS[remaining]) + 3
			check(at_sprite_pixel(red, center_x, 7).is_equal_approx(Color("#d95763")), "Authored red damage frame was not rendered")
		bar.call(&"_process", 0.08)
		check(not bool(bar.get("flash_visible")), "Damage blink did not alternate to empty")
		bar.call(&"_process", 0.4)
		check(int(bar.get("flash_mask")) == 0, "Damage blink did not expire")
		await capture("vida_personagem_%d_blocos" % remaining)
	bar.value = 60.0
	bar.value = 18.0
	check(int(bar.get("flash_mask")) == 60, "Large damage did not mark every lost block")
	bar.value = 60.0
	check(int(bar.get("flash_mask")) == 0 and is_zero_approx(float(bar.get("flash_remaining"))), "Healing did not cancel the red pulse")
	bar.max_value = 120.0
	bar.value = 120.0
	bar.value = 100.0
	check(int(bar.get("lit_blocks")) == 5, "Block mapping did not follow max-health changes")
	layer.queue_free()
	await process_frame
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	var arena: Node2D = current_scene as Node2D
	var boss: Node2D = arena.get_node("MinotaurChair") as Node2D
	boss.set("auto_start_encounter", false)
	boss.set_physics_process(false)
	var encounter: Node = boss.get_node("TutorialEncounter")
	var completion: Node = encounter.get("completion") as Node
	var live_bar: Range = completion.get_node("Nox/HP") as Range
	check(live_bar.get_script() == BAR_SCRIPT, "Tutorial HUD did not receive the reusable player bar")
	check(not completion.has_node("Nox/Name"), "Tutorial still displays the numeric health label")
	await create_timer(2.7).timeout
	var player: Player = arena.get_node("Mox") as Player
	player.intro_locked = false
	player.receive_skybreaker_hit(12.0)
	check(live_bar.value == 48.0 and int(live_bar.get("lit_blocks")) == 5, "Real player damage did not update the sprite HUD")
	var effects: CombatEffects = encounter.get("effects") as CombatEffects
	check(not effects.explosion_visuals_enabled, "Tutorial still enables the legacy blue impact burst")
	var target: DamageTarget = DamageTarget.new()
	target.position = Vector2(800, 800)
	arena.add_child(target)
	target.add_to_group(&"enemy_bodies")
	effects.trigger_explosion(target.global_position, 24.0, 7.0)
	check(target.health == 93.0, "Removing blue visuals changed explosion damage")
	check(effects.active_explosion_visuals.is_empty(), "Legacy blue burst was still instantiated")
	await create_timer(0.4).timeout
	await capture("tutorial_vida_personagem_atual")
	change_scene_to_file("res://scenes/dungeon/dungeon_preview.tscn")
	await process_frame
	await process_frame
	var dungeon_bar: Range = current_scene.get_node("HUD/Frame/Column/Health") as Range
	check(dungeon_bar.get_script() == BAR_SCRIPT, "Dungeon preview still uses numeric health")
	print("PLAYER LIFE BAR / LEGACY BLUE IMPACT: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
