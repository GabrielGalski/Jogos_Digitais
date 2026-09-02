extends SceneTree


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var enemies := main.get_node("Enemies") as Node2D
	var player := main.get_node("Player") as Player
	if enemies.call(&"get_showcase_mode_name") != &"minotaurs":
		_fail("the showcase should start in Minotaur mode")
		return
	if _active_group_count(&"minotaurs", enemies) != 3:
		_fail("Minotaur mode should start with exactly three enemies")
		return

	enemies.set_process(false)
	enemies.call(&"start_spirit_projection")
	if enemies.call(&"get_showcase_mode_name") != &"spirit_projection":
		_fail("the first Space mode should activate the Spirit projection")
		return
	if _active_group_count(&"spirit_ghosts", enemies) != 1:
		_fail("Spirit projection should begin immediately with one normal ghost")
		return
	if _active_group_count(&"minotaurs", enemies) != 0:
		_fail("queued Minotaurs should no longer count as active after the mode switch")
		return

	var first_ghost := _first_active_in_group(&"spirit_ghosts", enemies) as SpiritGhost
	first_ghost.set_physics_process(false)
	var normal_speed := first_ghost.movement_speed
	if first_ghost.is_empowered() or first_ghost.sprite.animation != &"move":
		_fail("ghosts should use their normal form before the elite arrives")
		return

	enemies.call(&"_process", 9.9)
	if _active_group_count(&"spirit_ghost_elite", enemies) != 0:
		_fail("the Spirit elite must not appear before ten seconds")
		return
	enemies.call(&"_process", 0.11)
	if _active_group_count(&"spirit_ghost_elite", enemies) != 1:
		_fail("exactly one Spirit elite should appear after ten seconds")
		return

	var elite := _first_active_in_group(&"spirit_ghost_elite", enemies) as SpiritGhostElite
	elite.set_physics_process(false)
	var elite_sprite := elite.get_node("Sprite") as AnimatedSprite2D
	if elite_sprite.sprite_frames.get_frame_count(&"move") != 4:
		_fail("the Spirit elite should animate all four supplied frames")
		return
	if not elite_sprite.scale.is_equal_approx(Vector2.ONE * 2.1):
		_fail("the Spirit elite should retain the enlarged elite presentation")
		return
	var elite_shadow := elite.get_node("GroundShadow") as Node2D
	var elite_shadow_color: Color = elite_shadow.get(&"color")
	if (
		not is_equal_approx(float(elite_shadow.get(&"radius")), 9.0)
		or elite_shadow.position != Vector2(0.0, 21.0)
		or not is_equal_approx(elite_shadow_color.a, 0.16)
	):
		_fail("the Spirit elite shadow should stay subtle, centered, and fixed below it")
		return

	for ghost_node in get_nodes_in_group(&"spirit_ghosts"):
		if ghost_node.get_parent() != enemies or ghost_node.is_queued_for_deletion():
			continue
		var ghost := ghost_node as SpiritGhost
		ghost.set_physics_process(false)
		if not ghost.is_empowered():
			_fail("the elite should transform every active Spirit Ghost")
			return
		if ghost.contact_damage != 2 or ghost.resistance < 2:
			_fail("transformed ghosts should receive the increased damage and resistance")
			return
		if ghost.sprite.animation != &"empowered_move":
			_fail("transformed ghosts should use the smaller elite visual family")
			return
	if not is_equal_approx(first_ghost.movement_speed, normal_speed * 1.5):
		_fail("existing ghosts should receive the configured speed multiplier")
		return

	var ghosts_before := _active_group_count(&"spirit_ghosts", enemies)
	enemies.call(&"_process", 0.42)
	if _active_group_count(&"spirit_ghosts", enemies) != ghosts_before + 1:
		_fail("Spirit Ghosts should continue spawning while the elite is present")
		return
	var newest_ghost := enemies.get_child(enemies.get_child_count() - 1) as SpiritGhost
	if not newest_ghost.is_empowered():
		_fail("new ghosts should spawn already transformed after the elite arrives")
		return

	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	elite.global_position = Vector2(90.0, 0.0)
	var distance_before := elite.global_position.distance_to(player.global_position)
	elite.call(&"_physics_process", 0.1)
	if elite.global_position.distance_to(player.global_position) <= distance_before:
		_fail("the Spirit elite should flee from the Player")
		return
	var safe_bounds := (main.get_node("Arena") as Arena).get_player_bounds().grow(-24.0)
	if not safe_bounds.has_point(elite.global_position):
		_fail("the fleeing Spirit elite should remain inside the arena")
		return

	enemies.call(&"restore_minotaur_showcase")
	if enemies.call(&"get_showcase_mode_name") != &"minotaurs":
		_fail("the second Space mode should restore the Minotaur showcase")
		return
	if _active_group_count(&"spirit_ghosts", enemies) != 0:
		_fail("restoring Minotaurs should clear all Spirit Ghosts")
		return
	if _active_group_count(&"spirit_ghost_elite", enemies) != 0:
		_fail("restoring Minotaurs should clear the Spirit elite")
		return
	if _active_group_count(&"minotaurs", enemies) != 3:
		_fail("restoring the showcase should create exactly three Minotaurs")
		return

	print("SPIRIT_PROJECTION_SMOKE_OK")
	quit(0)


func _active_group_count(group: StringName, parent: Node) -> int:
	var count := 0
	for node in get_nodes_in_group(group):
		if node.get_parent() == parent and not node.is_queued_for_deletion():
			count += 1
	return count


func _first_active_in_group(group: StringName, parent: Node) -> Node:
	for node in get_nodes_in_group(group):
		if node.get_parent() == parent and not node.is_queued_for_deletion():
			return node
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
