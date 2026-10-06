extends SceneTree

const OUTPUT_PATH := "res://.godot/reward_toast_capture.png"
const REWARD_TOAST: PackedScene = preload("res://scenes/visual/booster_reward_toast.tscn")

func _initialize() -> void:
	call_deferred(&"run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node = main.get_node("TutorialArena")
	var player: Node2D = arena.get_node("Mox") as Node2D
	await arena.entrance_finished
	var toast := REWARD_TOAST.instantiate() as Node2D
	arena.add_child(toast)
	toast.call(&"play", player.global_position + Vector2(0.0, -28.0), "Monster Booster vol. 1")
	await create_timer(0.16).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUTPUT_PATH)
	quit()
