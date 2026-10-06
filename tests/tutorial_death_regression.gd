extends SceneTree

func _initialize() -> void:
	call_deferred(&"run")

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var arena: Node = main.get_node("TutorialArena")
	await arena.entrance_finished
	var player: Player = arena.get_node("Mox") as Player
	player.receive_skybreaker_hit(60.0)
	assert(player.dead and player.health == 0.0)
	assert(not arena.exit_available)
	var previous: int = main.get_instance_id()
	for frame: int in range(110):
		await physics_frame
	assert(current_scene.get_instance_id() != previous)
	var fresh: Player = current_scene.get_node("TutorialArena/Mox") as Player
	assert(fresh.health == 60.0 and not fresh.dead)
	print("TUTORIAL_DEATH_RESTART_OK")
	quit()
