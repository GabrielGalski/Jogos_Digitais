extends SceneTree

const OUTPUT_PATH := "res://.godot/stair_direction_capture.png"

func _initialize() -> void:
	call_deferred(&"run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node = main.get_node("TutorialArena")
	var player: Node2D = arena.get_node("Mox") as Node2D
	var boss: Node = arena.get_node("MinotaurChair")
	var completion: Node = boss.tutorial_encounter.completion
	await arena.entrance_finished
	player.global_position += Vector2(52.0, -42.0)
	completion.stair_direction.call(&"point_to", arena.stair, player)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUTPUT_PATH)
	quit()
