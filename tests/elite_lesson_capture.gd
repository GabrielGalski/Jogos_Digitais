extends SceneTree

const OUTPUT_PATH := "res://.godot/elite_lesson_capture.png"

func _initialize() -> void:
	call_deferred(&"run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node = main.get_node("TutorialArena")
	var boss: Node = arena.get_node("MinotaurChair")
	var encounter: Node = boss.tutorial_encounter
	var completion: Node = encounter.completion
	await arena.entrance_finished
	encounter.phase = encounter.Phase.BOSS
	completion._boss_health(270.0, 270.0)
	completion._explain_elite(Vector2.ZERO)
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	completion.elite_ok.emit_signal(&"pressed")
	quit()
