extends SceneTree

class TestEnemy extends Node2D:
	var hp: float = 18.0
	var last_hit_direction: Vector2 = Vector2.RIGHT
	func is_alive() -> bool:
		return hp > 0.0
	func take_damage(amount: float) -> void:
		hp = maxf(0.0, hp - amount)

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("CARDS/TIN FAIL: " + message)

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _tap_e() -> void:
	_key(KEY_E, true)
	await process_frame
	_key(KEY_E, false)
	await process_frame

func _run() -> void:
	root.size = Vector2i(960, 540)
	_test_cards()
	change_scene_to_file("res://scenes/merchant_corridor.tscn")
	await create_timer(2.3).timeout
	var hall: Node2D = current_scene as Node2D
	var tin: MerchantInteractable = hall.get_node("World/Merchant") as MerchantInteractable
	var dialogue: DialogueBox = hall.get_node("TinDialogue") as DialogueBox
	var nox: Node2D = hall.get_node("Nox") as Node2D
	var visual: AnimatedSprite2D = tin.get_node("Visual") as AnimatedSprite2D
	var prompt: Label = hall.get_node("InteractionHUD/PromptAnchor/Prompt") as Label
	_check(visual.is_playing() and visual.sprite_frames.get_frame_count(&"idle") == 5, "Tin has five playing idle frames")
	_check(not tin.has_node("ContactShadow"), "no projected contact shadow")
	_check(not tin.can_interact(nox) and not prompt.visible, "far away cannot interact")
	await _tap_e()
	_check(not dialogue.is_dialogue_active(), "E from afar does nothing")
	hall.set("ground_position", Vector2(338.0, 16.0))
	await create_timer(0.15).timeout
	_check(tin.can_interact(nox) and prompt.visible, "near counter shows E prompt")
	await _tap_e()
	_check(dialogue.is_dialogue_active() and int(hall.get("state")) == 4, "E opens greeting")
	_check(dialogue.current_line_index() == 0 and dialogue.is_revealing_text(), "opening E does not also skip greeting")
	_check(dialogue.name_label.text == "TIN", "merchant keeps Tin name")
	var start: Vector2 = hall.get("ground_position")
	_key(KEY_D, true)
	await create_timer(0.2).timeout
	_key(KEY_D, false)
	_check(start.is_equal_approx(hall.get("ground_position")), "conversation locks movement")
	await _tap_e()
	_check(dialogue.is_dialogue_active() and not dialogue.is_revealing_text(), "E reveals text first")
	await _tap_e()
	_check(not dialogue.is_dialogue_active() and int(hall.get("state")) == 2, "E closes without reopening")
	_key(KEY_D, true)
	await create_timer(0.12).timeout
	_key(KEY_D, false)
	_check((hall.get("ground_position") as Vector2).x > start.x, "movement resumes")
	await _tap_e()
	_check(dialogue.is_dialogue_active(), "greeting is repeatable")
	dialogue.close_dialogue()
	hall.set("ground_position", Vector2(600.0, 28.0))
	await physics_frame
	await physics_frame
	_check(not prompt.visible, "prompt disappears after leaving")
	change_scene_to_file("res://scenes/dungeon/dungeon_preview.tscn")
	await create_timer(0.7).timeout
	var player: Player = current_scene.get_node("Nox") as Player
	var gun: Node2D = player.get_node("BoosterShooter") as Node2D
	var runtime: CardCombatRuntime = gun.get("card_runtime") as CardCombatRuntime
	var optional: CardLoadout = load("res://resources/cards/starter_loadout.tres").duplicate(true) as CardLoadout
	optional.mutation = load("res://resources/cards/fury_heart.tres") as MutationCard
	_check(bool(gun.call("equip_cards", optional)), "live caster accepts typed loadout")
	runtime.create_attack().on_weapon_kill.call()
	await process_frame
	await process_frame
	_check(player.card_movement_multiplier == 1.2, "mutation reaches live Nox movement multiplier")
	gun.call("equip_cards", CardLoadout.new())
	gun.set("cooldown", 0.0)
	_check(gun.call("fire_once") == null and player.card_movement_multiplier == 1.0, "live caster with no manifestation cannot shoot")
	gun.call("equip_cards", optional)
	gun.set("cooldown", 0.0)
	var bullet: RapidElectricBullet = gun.call("fire_once") as RapidElectricBullet
	_check(bullet != null and bullet.card_attack != null, "live caster emits card snapshot")
	runtime.create_attack().on_weapon_kill.call()
	gun.call("_reset_card_effects")
	_check(player.card_movement_multiplier == 1.0 and runtime.mutation_remaining == 0.0, "death reset removes mutation")
	print("CARDS/TIN REVIEW: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func _test_cards() -> void:
	var starter: CardLoadout = load("res://resources/cards/starter_loadout.tres") as CardLoadout
	var runtime: CardCombatRuntime = CardCombatRuntime.new()
	_check(starter.validation_errors().is_empty() and starter.mutation == null, "starter valid and mutation empty")
	_check(runtime.equip(starter), "equip starter")
	var shot: CardAttack = runtime.create_attack()
	_check(shot.damage == 3.0 and shot.explosion_damage == 3.0 and shot.explosion_radius == 18.0, "preserved 3+3/18px balance")
	_check(is_equal_approx(shot.fire_interval, 0.18) and shot.projectile_speed == 180.0 and is_equal_approx(shot.projectile_lifetime, 1.4), "preserved cadence/speed/lifetime")
	var effects: CombatEffects = CombatEffects.new()
	root.add_child(effects)
	var enemies: Array[TestEnemy] = []
	for index: int in range(3):
		var enemy: TestEnemy = TestEnemy.new()
		root.add_child(enemy)
		enemy.position = Vector2(float(index) * 10.0, 0.0)
		enemy.add_to_group(&"enemy_bodies")
		enemies.append(enemy)
	enemies[2].position.x = 100.0
	shot.resolve_hit(enemies[0], Vector2.ZERO, Vector2.RIGHT, effects)
	_check(enemies[0].hp == 12.0 and enemies[1].hp == 15.0 and enemies[2].hp == 18.0, "primary+AoE damage and radius")
	shot.resolve_hit(enemies[0], Vector2.ZERO, Vector2.RIGHT, effects)
	_check(enemies[0].hp == 12.0, "one infusion per emission, no repeated hit")
	var plain: CardLoadout = starter.duplicate(true) as CardLoadout
	plain.infusion = null
	runtime.equip(plain)
	_check(runtime.create_attack().explosion_damage == 0.0, "empty infusion adds no effect")
	_check(shot.explosion_damage == 3.0, "old projectile retains snapshot after swap")
	var visuals_before: int = effects.get_child_count()
	runtime.create_attack().resolve_hit(enemies[0], Vector2.ZERO, Vector2.RIGHT, effects)
	_check(enemies[0].hp == 9.0 and effects.get_child_count() == visuals_before, "uninfused shot does not spawn explosion")
	var fury: CardLoadout = starter.duplicate(true) as CardLoadout
	fury.mutation = load("res://resources/cards/fury_heart.tres") as MutationCard
	runtime.equip(fury)
	var old_shot: CardAttack = runtime.create_attack()
	enemies[0].hp = 3.0
	enemies[1].hp = 3.0
	old_shot.resolve_hit(enemies[0], Vector2.ZERO, Vector2.RIGHT, effects)
	_check(enemies[0].hp == 0.0 and enemies[1].hp == 0.0 and runtime.movement_multiplier() == 1.2, "direct and infusion kills trigger non-stacking mutation")
	runtime.tick(1.0)
	old_shot.on_weapon_kill.call()
	_check(runtime.mutation_remaining == 3.0 and runtime.movement_multiplier() == 1.2, "kill refreshes rather than stacks")
	runtime.tick(3.1)
	_check(runtime.movement_multiplier() == 1.0, "mutation expires")
	runtime.equip(fury)
	old_shot.on_weapon_kill.call()
	_check(runtime.movement_multiplier() == 1.0, "old build kill cannot activate new mutation")
	var other: CardCombatRuntime = CardCombatRuntime.new()
	other.equip(fury)
	runtime.create_attack().on_weapon_kill.call()
	_check(other.movement_multiplier() == 1.0, "runtime state never shared between casters")
	var invalid: CardLoadout = fury.duplicate(true) as CardLoadout
	invalid.manifestation.fire_interval = 0.0
	_check(not runtime.equip(invalid), "invalid data rejected without replacing loadout")
	runtime.equip(CardLoadout.new())
	_check(runtime.create_attack() == null and runtime.movement_multiplier() == 1.0, "empty manifestation prevents attacks")
	for enemy: TestEnemy in enemies:
		enemy.free()
	effects.free()
