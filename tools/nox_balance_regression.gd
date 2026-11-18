extends SceneTree
## Production hit registration: 12-HP minions, 9 melee hits / 17 sword impacts.

const MINION: PackedScene = preload("res://scenes/enemies/minotaur.tscn")

var _checks: int = 0
var _failures: int = 0
var _arena: Node2D = null
var _player: Player = null
var _boss: Node2D = null
var _actor: Node2D = null
var _encounter: Node = null
var _kit: Node2D = null
var _melee: Node2D = null
var _sword: Node2D = null
var _reticle: Sprite2D = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(480, 270)
	await _setup_tutorial()
	_check(is_equal_approx(_player.max_health, 60.0), "vida de Nox permanece 60")
	_check(is_equal_approx(float(_melee.get("damage")), 30.0), "melee configura dano 30")
	_check(is_equal_approx(float(_sword.get("damage")), 15.0), "boomerang configura dano 15")
	for state: int in [0, 1, 2, 6, 7]:
		_sword.call("_set_state", state)
		_check(_reticle.is_visible_in_tree(), "mira visivel no estado %d da espada" % state)
	_sword.call("reset_sword")
	_kit.call("set_combat_enabled", false)
	_check(_reticle.is_visible_in_tree(), "bloquear combate nao oculta mira")
	_kit.call("set_combat_enabled", true)
	_kit.call("set_throw_enabled", false)
	_check(_reticle.is_visible_in_tree(), "bloquear arremesso nao oculta mira")
	_kit.call("set_throw_enabled", true)
	paused = true
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(170.0, 90.0)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await process_frame
	_check(_reticle.can_process() and _reticle.position.is_equal_approx(motion.position), "mira acompanha mouse com gameplay pausado")
	_check(not _melee.can_process() and not _sword.can_process(), "mira ativa nao libera processamento de combate na pausa")
	paused = false
	# A single swept pass must kill both regular and empowered minions.
	for empowered: bool in [false, true]:
		var enemy: Minotaur = MINION.instantiate() as Minotaur
		enemy.position = Vector2(110.0, 150.0)
		enemy.training_dummy = true
		_arena.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.set_empowered(empowered)
		_check(is_equal_approx(enemy.resistance, 12.0), "minion inicia com 12 HP (fortalecido=%s)" % empowered)
		await physics_frame
		_clear_sword_hits()
		_sword.call("_apply_damage", enemy.global_position - Vector2(30.0, 0.0), enemy.global_position + Vector2(30.0, 0.0))
		_check(not enemy.is_alive() and is_zero_approx(enemy.resistance), "um impacto de boomerang elimina minion (fortalecido=%s)" % empowered)
		enemy.queue_free()
		await process_frame
	# Use the real attack's damage sector and per-attack latch, without animation timing.
	for hit: int in range(1, 10):
		_melee.set("_cooldown", 0.0)
		_check(bool(_melee.call("try_attack", Vector2.RIGHT)), "golpe melee %d inicia" % hit)
		_melee.call("_hit_in_reach")
		var expected: float = maxf(250.0 - float(hit) * 30.0, 0.0)
		_check(is_equal_approx(float(_boss.get("health")), expected), "vida apos melee %d = %.0f" % [hit, expected])
		_melee.call("_hit_in_reach")
		_check(is_equal_approx(float(_boss.get("health")), expected), "mesmo golpe melee nao repete dano")
		_melee.call("_finish_attack")
	_check(int(_boss.get("state")) == _boss.State.DEFEATED, "nono melee derrota Asterion")
	_check(int(_encounter.get("phase")) == 8, "nono melee dispara rendicao real")
	await _setup_tutorial()
	# Each impact represents a new throw; its whole journey cannot hit twice.
	for hit: int in range(1, 18):
		_clear_sword_hits()
		_sword.call("_apply_damage", _actor.global_position - Vector2(30.0, 0.0), _actor.global_position + Vector2(30.0, 0.0))
		var expected: float = maxf(250.0 - float(hit) * 15.0, 0.0)
		_check(is_equal_approx(float(_boss.get("health")), expected), "vida apos boomerang %d = %.0f" % [hit, expected])
		_sword.call("_apply_damage", _actor.global_position - Vector2(30.0, 0.0), _actor.global_position + Vector2(30.0, 0.0))
		_check(is_equal_approx(float(_boss.get("health")), expected), "mesmo lancamento da espada nao repete dano")
	_check(int(_boss.get("state")) == _boss.State.DEFEATED, "decimo setimo impacto derrota Asterion")
	_check(int(_encounter.get("phase")) == 8, "boomerang dispara rendicao real")
	var bar: Range = _encounter.get_node("Completion/Boss/HP") as Range
	_check(is_equal_approx(bar.max_value, 250.0) and is_zero_approx(bar.value), "HUD acompanha os 250 HP ate zero")
	_player.dead = true
	_player.defeated.emit()
	_check(_reticle.is_visible_in_tree(), "derrota nao oculta mira")
	print("NOX_BALANCE: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _setup_tutorial() -> void:
	paused = false
	change_scene_to_file("res://scenes/tutorial_arena.tscn")
	await process_frame
	await process_frame
	_arena = current_scene as Node2D
	_player = _arena.get_node("Mox") as Player
	_boss = _arena.get_node("MinotaurChair") as Node2D
	_boss.set("auto_start_encounter", false)
	for frame: int in range(360):
		if bool(_arena.get("entrance_complete")):
			break
		await physics_frame
	_check(bool(_arena.get("entrance_complete")), "entrada conclui antes do teste de combate")
	_encounter = _boss.get_node("TutorialEncounter")
	_encounter.set("phase", 7)
	_boss.set_physics_process(false)
	_boss.set("state", _boss.State.CHASE)
	_actor = _boss.get("actor") as Node2D
	_actor.global_position = Vector2(50.0, 65.0)
	_player.position = _actor.global_position - Vector2(28.0, 0.0)
	_player.intro_locked = false
	_player.set_physics_process(false)
	_kit = _player.get_node("GameplayKit") as Node2D
	_melee = _player.get_node("Melee") as Node2D
	_sword = _player.get_node("Sword") as Node2D
	_reticle = _arena.get_node("ArenaUI/Crosshair") as Sprite2D
	_kit.call("set_combat_enabled", true)
	_kit.call("set_throw_enabled", true)
	_check(is_equal_approx(float(_boss.get("health")), 250.0), "Asterion comeca com 250 HP")
	await physics_frame


func _clear_sword_hits() -> void:
	var hits: Dictionary[int, bool] = _sword.get("_hit_targets") as Dictionary[int, bool]
	hits.clear()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("[NOX BALANCE] " + message)
