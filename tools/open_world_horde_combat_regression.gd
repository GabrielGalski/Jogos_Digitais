extends SceneTree

const ENEMY: Script = preload("res://scripts/enemies/open_world_horde_enemy.gd")
const CATALOG: Script = preload("res://scripts/enemies/open_world_horde_catalog.gd")
const SHOT: Script = preload("res://scripts/combat/projectiles/open_world_horde_shot.gd")
var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	if not value:
		errors.append(label)
		push_error(label)


func _run() -> void:
	var world: Node2D = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	world.set("warp_entry_cutscene_enabled", false)
	root.add_child(world)
	while not bool(world.get("entry_complete")):
		await process_frame
	var player: Player = world.get_node("Nox") as Player
	var actors: Node2D = Node2D.new()
	world.add_child(actors)
	player.global_position = Vector2(1880, 1952)
	var hits: int = 0
	for kind: String in CATALOG.TYPES:
		var enemy: ENEMY = ENEMY.new()
		enemy.configure(kind, player, Callable())
		enemy.position = player.position - Vector2.RIGHT * (175.0 if kind == "ghost" else 18.0)
		actors.add_child(enemy)
		await physics_frame
		var distance: float = enemy.global_position.distance_to(player.global_position)
		enemy.cooldown = 0.0
		enemy.combat_direction(Vector2.RIGHT, 300.0, 0.1)
		check(enemy.windup == 0.0, kind + " waits outside range")
		enemy.combat_direction(Vector2.RIGHT, distance, 0.01)
		check(enemy.windup > 0.0, kind + " acquires the player")
		enemy.combat_direction(Vector2.RIGHT, distance, 0.26)
		var shot: SHOT = actors.get_child(-1) as SHOT
		check(shot != null, kind + " fires")
		if shot != null:
			check(shot.sheet == enemy.stats.shot and shot.art.hframes == int(enemy.stats.frames), kind + " attack sheet")
			player.contact_invulnerability = 0.0
			var before: float = player.health
			shot._physics_process(0.1)
			for step: int in range(160):
				if shot.consumed:
					break
				shot._physics_process(0.016)
			if player.health < before:
				hits += 1
			player.health = before
			if kind == "lizard_monk":
				enemy.combat_direction(Vector2.RIGHT, distance, 0.19)
				check(actors.get_child(-1) is SHOT and actors.get_child(-1) != shot, "Monk fires its second bolt")
			if kind == "batilisk":
				check(actors.get_child(-1) is Sprite2D, "Firebolt creates impact animation")
		var body_scale: Vector2 = enemy.scale
		enemy.take_damage(1.0)
		enemy._process(0.02)
		var visual: Sprite2D = enemy.get_node("Sprite") as Sprite2D
		check(float((visual.material as ShaderMaterial).get_shader_parameter("flash_amount")) == 1.0, kind + " white hit flash")
		check(visual.scale.x > 1.0 and visual.offset.y < 0.0 and enemy.scale == body_scale, kind + " visual squash and bounce")
		enemy.take_damage(1.0)
		enemy._process(0.22)
		check(visual.scale.is_equal_approx(Vector2.ONE) and visual.offset.is_zero_approx(), kind + " recovers from repeated hit")
		for child: Node in actors.get_children():
			child.queue_free()
		await process_frame
	check(hits == CATALOG.TYPES.size(), "All seven attacks reach and damage the player (%d/7)" % hits)
	player.contact_invulnerability = 1000.0
	for totem: Node2D in world.get_node("HordePedestals").get("pedestals") as Array:
		var encounter: Node2D = totem.get("encounter") as Node2D
		# Exercise the regular horde branch with no miniboss roll.
		(encounter.get("profile") as Resource).set("miniboss_spawn_chance", 0.0)
		player.global_position = totem.global_position + Vector2(20.0, 0.0)
		player.snap_floor_height()
		var camera: Camera2D = player.get_node("Camera2D") as Camera2D
		camera.reset_smoothing()
		camera.force_update_scroll()
		encounter.call("begin")
		for frame: int in range(1200):
			if int(encounter.get("_opening_remaining")) <= 0:
				break
			await physics_frame
		check(int(encounter.get("_opening_remaining")) == 0, "Opening wave finishes spawning")
		var tally: Dictionary = {}
		encounter.set_physics_process(false)
		if totem == (world.get_node("HordePedestals").get("pedestals") as Array).front():
			for index: int in range(100):
				encounter.call("_spawn_one")
			var live: Array = encounter.get("actors") as Array
			check(live.size() == 48, "Horde population stops at forty-eight live enemies")
			for actor: Node2D in live:
				for index: int in range(6):
					actor.call("_fire")
			check((encounter.get("projectiles") as Array).size() == 96, "Projectile budget stops at ninety-six simultaneous shots")
			for count: int in (encounter.get("_projectiles_by_shooter") as Dictionary).values():
				check(count <= 3, "Each shooter respects its three-projectile budget")
			for shot: Node2D in (encounter.get("projectiles") as Array).duplicate():
				shot.call("dismiss")
			await physics_frame
			await process_frame
			check((encounter.get("projectiles") as Array).is_empty() and (encounter.get("_projectiles_by_shooter") as Dictionary).is_empty(), "Expired shots return both global and individual slots")
		for attempt: int in range(600):
			var live: Array = encounter.get("actors") as Array
			var enemy: ENEMY = live.front() as ENEMY if not live.is_empty() else encounter.call("_spawn_one") as ENEMY
			if enemy != null:
				tally[enemy.species] = int(tally.get(enemy.species, 0)) + 1
				enemy.take_damage(100.0)
			if int(encounter.get("phase")) == 2:
				break
		var id: String = str(encounter.get("encounter_id"))
		check(int(encounter.get("defeated_count")) == 120 and int(encounter.get("phase")) == 2, id + " kill criterion and completion")
		check(encounter.get("completion_reason") == &"kills", id + " exposes completion reason")
	world.queue_free()
	await process_frame
	print("OPEN_WORLD_HORDE_COMBAT ", errors)
	quit(0 if errors.is_empty() else 1)
