extends SceneTree
## Real kit and contact sweeps for the Dragon cards and the three ricochet paths.

const CATALOG: Script = preload("res://scripts/cards/card_effect_catalog.gd")
const KIT: Script = preload("res://scripts/combat/player_gameplay_kit.gd")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const FACTORY: Script = preload("res://scripts/combat/manifestations/manifestation_factory.gd")
const VIEWER: PackedScene = preload("res://scenes/cards/booster_viewer.tscn")

class Enemy extends CharacterBody2D:
	var health: float = 100.0
	var impulse: float = 0.0

	func _ready() -> void:
		add_to_group(&"enemy_bodies")
		collision_layer = 4
		collision_mask = 0

	func is_alive() -> bool:
		return health > 0.0

	func get_current_health() -> float:
		return health

	func take_damage(amount: float) -> void:
		health = maxf(0.0, health - amount)

	func get_projectile_hurt_capsule() -> Dictionary:
		return {"center": Vector2.ZERO, "radius": 5.0, "height": 12.0}

	func receive_impact(_direction: Vector2, amount: float) -> void:
		impulse = amount

var arena: Node2D
var player: Player
var gun: Node2D
var driver: Node
var combat: CombatEffects
var runtime: CardCombatRuntime
var rewards: Node
var errors: int = 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	player = PLAYER.instantiate()
	arena.add_child(player)
	player.set_physics_process(false)
	var kit: Node2D = KIT.new()
	kit.name = "GameplayKit"
	kit.set("world_bounds", player.arena_bounds)
	player.add_child(kit)
	kit.set_process(false)
	gun = player.get_node("BoosterShooter")
	driver = kit.get_node("Manifestations")
	combat = kit.get_node("ShooterEffects")
	runtime = gun.get("card_runtime")
	rewards = root.get_node("BoosterRewards")
	await ticks(2)
	await test_reflections()
	await test_spiral()
	await test_infusions_and_mutations()
	test_pack()
	print("DRAGON CARDS ", "PASS" if errors == 0 else "FAIL (%d)" % errors)
	quit(0 if errors == 0 else 1)


func test_reflections() -> void:
	var wall: StaticBody2D = StaticBody2D.new()
	wall.position.x = 48.0
	var body: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(4, 200)
	body.shape = rectangle
	wall.add_child(body)
	arena.add_child(wall)
	var aim: Vector2 = Vector2(1, 0.5).normalized()
	var enemy: Enemy = spawn(Vector2(24, 34))
	var blocked: Enemy = spawn(Vector2(60, 30))
	driver.call("select_infusion", InfusionCard.GARGOYLE)
	await ticks(2)
	var shots: Node = driver.get("projectiles")
	var sprites: ProceduralWeaponSpriteFactory = driver.get("sprites")
	for code: StringName in [&"M01", &"M02", &"M07", &"M09"]:
		var model: ProceduralManifestationModel = equip(code)
		enemy.health = 100.0
		blocked.health = 100.0
		var origin: Vector2 = Vector2(24, 12) if code == &"M09" else Vector2.ZERO
		var shot: Node2D = FACTORY.projectile(model, runtime.create_attack(), shots, origin, aim, combat, player, sprites)
		await ticks(30)
		check(enemy.health < 100.0 and blocked.health == 100.0, "%s hits around the wall once (%s, %s)" % [code, enemy.health, blocked.health])
		if is_instance_valid(shot):
			shot.queue_free()
	var beholder: ProceduralManifestationModel = equip(&"M04")
	var beam: Node2D = FACTORY.channel(beholder, shots, player, sprites)
	driver.set("channel", beam)
	beam.call("advance", 0.25, Vector2.ZERO, aim, true, true)
	check(bool(beam.get("_beam_reflected")) and beam.get("beam_target") == enemy, "Beholder bends onto the reflected target")
	check((beam.call("hit_direction") as Vector2).x < 0.0, "Reflected beam damage follows the reflected direction")
	enemy.health = 100.0
	driver.call("_apply_channel_tick", beholder)
	check(enemy.health < 100.0, "Reflected beam deals real damage")
	driver.call("cancel_attacks")
	var stream: ProceduralManifestationModel = equip(&"M08")
	var flame: Node2D = FACTORY.channel(stream, shots, player, sprites)
	driver.set("channel", flame)
	flame.call("advance", 0.30, Vector2.ZERO, aim, true, true)
	enemy.health = 100.0
	blocked.health = 100.0
	var shot_count: int = get_nodes_in_group(&"manifestation_projectiles").size()
	driver.call("_apply_channel_tick", stream)
	check(enemy.health < 100.0 and blocked.health == 100.0 and get_nodes_in_group(&"manifestation_projectiles").size() == shot_count,
		"Sopro deals damage with the reflected channel, without spawning a separate shot")
	check((flame.call("hit_direction", enemy) as Vector2).x < 0.0, "Sopro uses the reflected direction on contact")
	driver.call("cancel_attacks")
	wall.queue_free()
	enemy.queue_free()
	blocked.queue_free()
	await ticks(2)


func test_spiral() -> void:
	driver.call("select_infusion", -1)
	equip(&"M11")
	gun.set("aim_screen_override", root.get_canvas_transform() * Vector2(220.0, 0.0))
	gun.call("_update_rig", 0.0)
	gun.set("cooldown", 0.0)
	var first: Node2D = gun.call("fire_once")
	gun.set("cooldown", 0.0)
	var second: Node2D = gun.call("fire_once")
	check(first != null and second != null, "Brasa can fire from the real weapon")
	if first == null or second == null:
		return
	var angle: float = absf((first.get("direction") as Vector2).angle_to(second.get("direction") as Vector2))
	await ticks(12)
	var wider: float = absf((first.get("direction") as Vector2).angle_to(second.get("direction") as Vector2))
	check(wider > angle, "Sequential embers spread as they travel")
	first.queue_free()
	second.queue_free()
	await ticks(2)


func test_infusions_and_mutations() -> void:
	equip(&"M01")
	driver.call("select_infusion", InfusionCard.EMBER_HEAT)
	var heated: Enemy = spawn(Vector2(45, 0))
	for hit: int in range(4):
		var attack: CardAttack = runtime.create_attack()
		attack.apply_primary_hit(heated, heated.position, Vector2.RIGHT, combat)
	check(heated.health < 88.0, "Fourth hit adds heat damage")
	heated.queue_free()
	await ticks(2)

	driver.call("select_infusion", InfusionCard.DRAGON_METEOR)
	driver.call("select_mutation", MutationCard.DRAGON_GREED)
	runtime.dragon_kills = 99
	var remaining_enemy: Enemy = spawn(Vector2(50, 0))
	var victim: Enemy = spawn(Vector2(32, 30))
	combat.apply_hit(victim, 1000.0, Vector2.ZERO, 0.0)
	combat.apply_hit(spawn(Vector2(60, 30)), 1000.0, Vector2.ZERO, 0.0)
	check(int(rewards.call("pending_count")) == 1 and runtime.dragon_kills == 1, "One booster per 100 credited kills")
	check(is_equal_approx(float(runtime.cooldowns.get(&"I12")), 6.0), "Meteor starts its six-second cooldown")
	await ticks(38)
	check(is_equal_approx(remaining_enemy.health, 88.0), "One allied meteor hits the remaining target")
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_B
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var viewer: BoosterViewer = arena.get_node_or_null("DragonGreedPack/BoosterViewer") as BoosterViewer
	check(viewer != null and paused, "B opens the queued booster")
	if viewer != null:
		var cards: Array[CardDefinition] = viewer.get("_reward")
		viewer.booster_opened.emit(cards)
		check(int(rewards.call("pending_count")) == 0 and int(rewards.call("count", cards[0].card_id)) > 0, "The opened pack grants its cards")
		viewer.close_viewer()
		await process_frame
	check(not paused, "Closing the pack resumes gameplay")

	driver.call("select_infusion", -1)
	driver.call("select_mutation", MutationCard.CRIMSON_WINGS)
	remaining_enemy.health = 100.0
	var boss: Enemy = spawn(Vector2(45, 10))
	boss.set_meta(&"is_boss", true)
	check(player.try_dash(Vector2.RIGHT), "Nox can dash with Crimson Wings")
	await ticks(23)
	check(is_equal_approx(remaining_enemy.health, 96.0) and remaining_enemy.impulse > 0.0 and boss.health == 100.0, "Wind hurts and pushes a minor foe once and leaves the boss alone")


func test_pack() -> void:
	var progress: Node = root.get_node("DragonProgress")
	progress.call("record_defeat")
	progress.call("record_defeat")
	var pack: Dictionary = progress.call("pending_reward")
	check(int(pack.volume) == CATALOG.DRAGON_PACK and pack.cards.size() == 3, "A Dragon defeat queues one dedicated pack")
	for card: CardDefinition in pack.cards:
		check(CATALOG.alias(card) in CATALOG.PACK_CODES[CATALOG.DRAGON_PACK - 1], "Dragon pack draws from its set")
	var viewer: BoosterViewer = VIEWER.instantiate()
	arena.add_child(viewer)
	viewer.open_pack(int(pack.volume), pack.cards)
	check((viewer.get("_pack") as Texture2D).resource_path.ends_with("sets/dragon/base.png"), "Dragon booster uses its own artwork")
	viewer.close_viewer()
	viewer.queue_free()
	progress.call("claim_reward")
	check((progress.call("pending_reward") as Dictionary).is_empty(), "Claiming the pack leaves no duplicate entitled reward")


func equip(code: StringName) -> ProceduralManifestationModel:
	for index: int in range(CATALOG.MANIFESTATIONS.size()):
		var model: ProceduralManifestationModel = CATALOG.MANIFESTATIONS[index]
		if model.code() == code:
			driver.call("select_model", index)
			return model
	return null


func spawn(point: Vector2) -> Enemy:
	var enemy: Enemy = Enemy.new()
	enemy.position = point
	arena.add_child(enemy)
	return enemy


func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
	await process_frame


func check(ok: bool, detail: String) -> void:
	if not ok:
		errors += 1
		push_error(detail)
