extends SceneTree

var received_damage := 0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var enemies: Node2D = main.get_node("Enemies")
	var player: Player = main.get_node("Player")
	var minotaurs := get_nodes_in_group(&"minotaurs").filter(
		func(node: Node) -> bool: return node.get_parent() == enemies
	)
	if minotaurs.size() != 3:
		_fail("play should start with exactly three Minotaurs")
		return
	if not get_nodes_in_group(&"spirit_ghosts").is_empty():
		_fail("Spirit Ghosts should no longer be spawned by the active MVP")
		return
	if not get_nodes_in_group(&"mimic_elite").is_empty():
		_fail("the Mimic should no longer be spawned by the active MVP")
		return

	for minotaur_node in minotaurs:
		(minotaur_node as Node).set_physics_process(false)
	player.set_physics_process(false)

	for first_index in range(minotaurs.size()):
		for second_index in range(first_index + 1, minotaurs.size()):
			var first := minotaurs[first_index] as Node2D
			var second := minotaurs[second_index] as Node2D
			var required_spacing := (
				float(first.call(&"get_separation_radius"))
				+ float(second.call(&"get_separation_radius"))
			)
			if first.global_position.distance_to(second.global_position) < required_spacing:
				_fail("Minotaur bodies overlapped during the initial spawn")
				return

	var minotaur := minotaurs[0] as Node2D
	var minotaur_sprite := minotaur.get_node("Sprite") as AnimatedSprite2D
	if minotaur_sprite.sprite_frames.get_frame_count(&"walk") != 4:
		_fail("all four supplied walk frames should be used")
		return
	if minotaur_sprite.sprite_frames.get_frame_count(&"attack") != 6:
		_fail("all six supplied attack frames should be used")
		return

	var player_body := player.get_node("Body") as AnimatedSprite2D
	if player.has_node("ProjectedShadow") or not player.has_node("GroundShadow"):
		_fail("the Player should use only the centered ground shadow")
		return
	var player_shadow := player.get_node("GroundShadow") as Node2D
	if not is_equal_approx(float(player_shadow.get(&"radius")), 4.0):
		_fail("the Player ground shadow should use a subtle four-pixel radius")
		return
	if player_shadow.position != Vector2(0.0, 7.0) or player_shadow.z_index != -1:
		_fail("the Player shadow should be centered directly below the sprite")
		return
	var player_shadow_color: Color = player_shadow.get(&"color")
	if not is_equal_approx(player_shadow_color.a, 0.16):
		_fail("the Player shadow should retain the subtle 0.16 opacity")
		return

	var minotaur_shadow := minotaur.get_node("GroundShadow") as Node2D
	if not is_equal_approx(float(minotaur_shadow.get(&"radius")), 5.5):
		_fail("the Minotaur should use its reduced 5.5-pixel circular shadow")
		return
	if minotaur_shadow.position != Vector2(0.0, 9.0) or minotaur_shadow.z_index != -1:
		_fail("the Minotaur circular shadow should remain underneath the sprite")
		return
	var minotaur_shadow_color: Color = minotaur_shadow.get(&"color")
	if not is_equal_approx(minotaur_shadow_color.a, 0.16):
		_fail("mob shadows should retain the subtle 0.16 opacity")
		return

	var ghost_preview: Node = load("res://scenes/enemies/spirit_ghost.tscn").instantiate()
	var mimic_preview: Node = load("res://scenes/enemies/elites/mimic.tscn").instantiate()
	if not ghost_preview.has_node("GroundShadow") or not mimic_preview.has_node("GroundShadow"):
		_fail("preserved mob scenes should also contain only simple circular shadows")
		return
	ghost_preview.free()
	mimic_preview.free()

	player.global_position = Vector2.ZERO
	minotaur.global_position = Vector2(150.0, 0.0)
	minotaur.call(&"_physics_process", 0.016)
	var previous_distance := minotaur.global_position.distance_to(player.global_position)
	minotaur.call(&"_physics_process", 0.1)
	if minotaur.global_position.distance_to(player.global_position) >= previous_distance:
		_fail("a distant Minotaur should walk toward the Player")
		return
	if minotaur.call(&"get_state_name") != &"walk" or minotaur_sprite.animation != &"walk":
		_fail("a distant Minotaur should use the walk state and animation")
		return

	var attacks_before := get_nodes_in_group(&"minotaur_melee_attacks").size()
	minotaur.global_position = Vector2(40.0, 0.0)
	minotaur.call(&"_physics_process", 0.1)
	if minotaur.call(&"get_state_name") != &"attack" or minotaur_sprite.animation != &"attack":
		_fail("a Minotaur inside the reduced melee distance should enter attack")
		return
	minotaur.global_position = Vector2(65.0, 0.0)
	minotaur.call(&"_physics_process", 0.01)
	minotaur.call(&"_physics_process", 0.5)
	if minotaur.call(&"get_state_name") != &"walk" or minotaur_sprite.animation != &"walk":
		_fail("leaving attack range should interrupt attack and resume walk immediately")
		return
	if get_nodes_in_group(&"minotaur_melee_attacks").size() != attacks_before:
		_fail("an attack interrupted before its windup should not create the melee effect")
		return

	minotaur.global_position = Vector2(40.0, 0.0)
	minotaur.call(&"_physics_process", 0.4)
	var melee_attacks := get_nodes_in_group(&"minotaur_melee_attacks").filter(
		func(node: Node) -> bool: return node.get_parent() == minotaur
	)
	if melee_attacks.size() != 1:
		_fail("the attack windup should activate one melee effect")
		return
	minotaur.call(&"_physics_process", 1.6)
	minotaur.call(&"_physics_process", 0.38)
	if get_nodes_in_group(&"minotaur_melee_attacks").size() != 2:
		_fail("the Minotaur should activate another melee attack every two seconds")
		return

	var melee_attack := melee_attacks[0] as Area2D
	var attack_sprite := melee_attack.get_node("Sprite") as AnimatedSprite2D
	if attack_sprite.sprite_frames.get_frame_count(&"attack_effect") != 4:
		_fail("all four supplied melee effect frames should be animated")
		return
	if attack_sprite.sprite_frames.get_animation_loop(&"attack_effect"):
		_fail("the Minotaur melee gradient should play only once")
		return
	if not melee_attack.scale.is_equal_approx(Vector2(0.5, 0.5)):
		_fail("the Minotaur melee model and collision should retain half scale")
		return
	for active_attack in get_nodes_in_group(&"minotaur_melee_attacks"):
		(active_attack as Node).set_physics_process(false)
	await create_timer(0.4).timeout
	if attack_sprite.frame != 3:
		_fail("the melee gradient should reach its fourth orange frame")
		return
	await create_timer(0.1).timeout
	if attack_sprite.frame != 3:
		_fail("the melee effect should remain orange until its short lifetime ends")
		return
	if melee_attack.collision_layer != 8 or melee_attack.collision_mask != 1:
		_fail("the Minotaur melee attack should collide exclusively with the Player")
		return

	player.contact_damage_received.connect(
		func(amount: int) -> void: received_damage += amount
	)
	melee_attack.call(&"_physics_process", 0.016)
	if not melee_attack.is_queued_for_deletion() or received_damage != 2:
		_fail("the melee model should damage the Player once and disappear on hit")
		return

	var remaining_attacks := get_nodes_in_group(&"minotaur_melee_attacks").filter(
		func(node: Node) -> bool: return not node.is_queued_for_deletion()
	)
	if remaining_attacks.size() != 1:
		_fail("one untouched melee effect should remain for the lifetime test")
		return
	var expiring_attack := remaining_attacks[0] as Area2D
	var stationary_position := expiring_attack.global_position
	player.global_position = Vector2(200.0, 0.0)
	expiring_attack.call(&"_physics_process", 0.44)
	if expiring_attack.is_queued_for_deletion():
		_fail("the melee effect disappeared before its configured short lifetime")
		return
	if not expiring_attack.global_position.is_equal_approx(stationary_position):
		_fail("the melee attack model should remain stationary instead of travelling")
		return
	expiring_attack.call(&"_physics_process", 0.02)
	if not expiring_attack.is_queued_for_deletion():
		_fail("the melee attack model should disappear shortly after activation")
		return
	if player_body.sprite_frames.has_animation(&"damage"):
		_fail("the old damage sprite must remain unused")
		return
	var damage_material := player_body.material as ShaderMaterial
	if not is_equal_approx(float(damage_material.get_shader_parameter(&"flash_amount")), 1.0):
		_fail("melee damage should turn the current Player frame white")
		return

	print("MINOTAUR_SMOKE_OK")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
