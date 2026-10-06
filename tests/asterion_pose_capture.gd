extends Node
const ARENA: PackedScene = preload("res://scenes/tutorial_arena.tscn")
func _ready() -> void:
	var arena: Node2D = ARENA.instantiate() as Node2D
	var boss: Variant = arena.get_node("MinotaurChair")
	boss.auto_start_encounter = false
	add_child(arena)
	boss.set_physics_process(false)
	for tween: Tween in get_tree().get_processed_tweens():
		tween.kill()
	var player: CharacterBody2D = arena.get_node("Mox") as CharacterBody2D
	player.set_physics_process(false)
	player.position = Vector2(0, -180)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.top_level = true
	camera.position = Vector2(0, -210)
	camera.position_smoothing_enabled = false
	camera.limit_top = -1000
	camera.limit_bottom = 1000
	camera.zoom = Vector2(2, 2)
	camera.reset_smoothing()
	boss.get_node("Asterion").pause()
	boss.get_node("Asterion").frame = 0
	await capture("01_sitting")
	boss._start_from_throne()
	await capture("02_standing")
	boss._finish_throne_standing()
	await capture("03_propulsion")
	boss._finish_throne_propulsion()
	await capture("04_takeoff")
	get_tree().quit()

func capture(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture_image: Image = get_viewport().get_texture().get_image()
	capture_image.save_png("res://docs/ai_validation/" + label + ".png")
