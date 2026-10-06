extends SceneTree

var hits: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred(&"run")

func run() -> void:
	var arena: Node2D = load("res://scenes/tutorial_arena.tscn").instantiate() as Node2D
	arena.get_node("MinotaurChair").set("auto_start_encounter", false)
	root.add_child(arena)
	for tick: int in range(220):
		await physics_frame
	var player: Player = arena.get_node("Mox") as Player
	player.damage_received.connect(func(_damage: float) -> void: hits += 1)
	for empowered: bool in [false, true]:
		for side: Vector2 in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
			player.position = Vector2(0, 100)
			player.knockback_velocity = Vector2.ZERO
			player.impact_control_lock = 0.0
			player.contact_invulnerability = 0.0
			var enemy: Minotaur = load("res://scenes/enemies/minotaur.tscn").instantiate() as Minotaur
			enemy.position = player.position + side * 46.0
			arena.add_child(enemy)
			enemy.setup(player, arena, player.arena_bounds)
			enemy.set_empowered(empowered)
			var initial_hits: int = hits
			var rebound: bool = false
			for tick: int in range(160):
				await physics_frame
				if hits > initial_hits:
					rebound = enemy.hit_velocity.dot(side) > 0.0 and player.knockback_velocity.dot(-side) > 0.0 and player.impact_control_lock > 0.0
					break
			if hits == initial_hits or (empowered and not rebound):
				failures += 1
				push_error("Minotaur regression empowered=%s side=%s hits=%s rebound=%s" % [empowered, side, hits - initial_hits, rebound])
			if empowered and enemy.sprite.animation != &"walk_attack":
				failures += 1
			enemy.queue_free()
			await physics_frame
	print("MINOTAUR_REGRESSION failures=%d hits=%d" % [failures, hits])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
