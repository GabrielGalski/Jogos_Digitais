extends SceneTree

class DummyEnemy extends Node2D:
	var health: float = 100.0
	var last_hit_direction: Vector2 = Vector2.RIGHT
	func is_alive() -> bool:
		return health > 0.0
	func take_damage(amount: float) -> void:
		health -= amount

class CountEffects extends CombatEffects:
	var bursts: int = 0
	func _spawn_explosion_visual(_center: Vector2, _radius: float) -> void:
		bursts += 1

var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var room: Node2D = Node2D.new()
	root.add_child(room)
	var effects: CountEffects = CountEffects.new()
	effects.camera_feedback_enabled = false
	room.add_child(effects)
	var enemies: Array[DummyEnemy] = []
	for point: Vector2 in [Vector2(60, 15), Vector2(85, -20), Vector2(50, 65), Vector2(-20, 0), Vector2(130, 0)]:
		var enemy: DummyEnemy = DummyEnemy.new()
		room.add_child(enemy)
		enemy.position = point
		enemy.add_to_group(&"enemy_bodies")
		enemies.append(enemy)
	var loadout: CardLoadout = CardLoadout.new()
	loadout.manifestation = load("res://resources/cards/preview/M03.tres") as ManifestationCard
	loadout.infusion = load("res://resources/cards/golem_core.tres") as InfusionCard
	var runtime: CardCombatRuntime = CardCombatRuntime.new()
	check(runtime.equip(loadout), "M03 loadout invalid")
	var burst: Node2D = load("res://scripts/dungeon/banshee_burst.gd").new() as Node2D
	room.add_child(burst)
	var attack: CardAttack = runtime.create_attack()
	burst.call("configure", Vector2.RIGHT, attack, effects)
	await create_timer(0.3).timeout
	check(enemies[0].health == 91.0 and enemies[1].health == 94.0, "cone must hit each interior enemy once")
	check(enemies[2].health == 100.0, "cone hits lateral enemy")
	check(enemies[3].health == 100.0, "cone hits behind shooter")
	check(enemies[4].health == 100.0, "cone exceeds reach")
	check(effects.bursts == 1, "cone repeats infusion across targets")
	check(attack.primary_hit_ids.size() == 2, "cone duplicate hit")
	await create_timer(0.1).timeout
	check(not is_instance_valid(burst), "cone visual not cleaned")
	print("BANSHEE REGRESSION: " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

