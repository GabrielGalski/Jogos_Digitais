extends Node
## Owns the first conversation, weapon reveal, minion encounter and return to throne.
enum Phase { INTRO, REVEAL, ARMED_DIALOGUE, OPENING, HORDE, RETURN, CHALLENGE, BOSS, VICTORY, FINISHED, LOST }
const COMPLETION: PackedScene = preload("res://scenes/tutorial_completion.tscn")
var completion: Node
@export var weapon_reveal_duration: float = 1.4
@export var return_distance: float = 52.0
@export var roar_minimum_duration: float = 1.2
@export var armed_dialogue: DialogueSequence = preload("res://resources/dialogue/asterion_armed.tres")
@export var roar_dialogue: DialogueSequence = preload("res://resources/dialogue/asterion_roar.tres")
@export var challenge_dialogue: DialogueSequence = preload("res://resources/dialogue/asterion_challenge.tres")
var phase: Phase = Phase.INTRO
var boss: Node2D
var player: Player
var dialogue: DialogueBox
var weapon: Node2D
var return_approach_started: bool = false
var elite_horde_started: bool = false
var reveal_time: float = 0.0
var return_time: float = 0.0
var skip_requested: bool = false
var reticle: Sprite2D
@onready var horde: Node2D = $Horde
@onready var effects: CombatEffects = $Effects
@onready var projectiles: Node2D = $Projectiles
@onready var hint: Label = $HUD/SafeArea/Hint

func setup(owner_boss: Node2D, arena: Node2D, owner_player: Player, box: DialogueBox) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child: Node in get_children():
		child.process_mode = Node.PROCESS_MODE_PAUSABLE
	boss = owner_boss
	player = owner_player
	dialogue = box
	weapon = player.get_node("GameplayKit") as Node2D
	weapon.call("bind_effects", effects)
	reticle = weapon.get("reticle") as Sprite2D
	horde.setup(player, arena)
	horde.horde_cleared.connect(_on_horde_cleared)
	horde.opening_arrived.connect(_on_opening_arrived)
	effects.camera_feedback_enabled = false
	# The restored M01 shooter owns its slime impact; no legacy blue burst.
	effects.explosion_visuals_enabled = false
	boss.skybreaker_started.connect(_on_boss_jump)
	boss.impact_started.connect(_on_boss_impact)
	hint.hide()
	completion = COMPLETION.instantiate()
	completion.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(completion)
	completion.setup(self)
	completion.lesson_dismissed.connect(_on_lesson_dismissed)

func begin_dialogue() -> void:
	if phase == Phase.RETURN:
		phase = Phase.CHALLENGE
		weapon.set_combat_enabled(false)
		hint.hide()
		dialogue.start_dialogue(challenge_dialogue)
	else:
		dialogue.start_dialogue(boss.intro_dialogue)

func on_dialogue_finished(sequence_id: StringName) -> void:
	if phase == Phase.INTRO and sequence_id == boss.intro_dialogue.sequence_id:
		phase = Phase.REVEAL
		reveal_time = 0.0
		boss.enter_weapon_reveal()
		weapon.reveal()
	elif phase == Phase.ARMED_DIALOGUE and sequence_id == armed_dialogue.sequence_id:
		phase = Phase.OPENING
		boss.enter_horde_phase()
		player.intro_locked = true
		weapon.set_combat_enabled(false)
		horde.start_horde()
	elif phase == Phase.CHALLENGE and sequence_id == challenge_dialogue.sequence_id:
		phase = Phase.BOSS
		player.heal_full()
		weapon.set_combat_enabled(true)
		boss._start_from_throne()

func _process(delta: float) -> void:
	if player == null:
		return
	if get_tree().paused:
		return
	if skip_requested and boss.arena.entrance_complete:
		skip_requested = false
		skip_to_boss()
	if phase == Phase.REVEAL:
		reveal_time += delta
		if reveal_time >= weapon_reveal_duration:
			phase = Phase.ARMED_DIALOGUE
			boss.enter_intro_dialogue_state()
			dialogue.start_dialogue(armed_dialogue)
	elif phase == Phase.RETURN and not return_approach_started:
		return_time += delta
		if return_time >= roar_minimum_duration and player.position.distance_to(boss.intro_destination) <= return_distance:
			return_approach_started = true
			if dialogue.is_dialogue_active():
				dialogue.close_dialogue()
			weapon.set_combat_enabled(false)
			boss._begin_player_approach()

func _on_opening_arrived() -> void:
	if phase != Phase.OPENING:
		return
	phase = Phase.HORDE
	player.intro_locked = false
	weapon.set_combat_enabled(true)
	effects.camera_feedback_enabled = true
	completion.show_controls_lesson()


func _on_lesson_dismissed(_lesson_id: StringName) -> void:
	pass

func _on_horde_cleared() -> void:
	if phase != Phase.HORDE:
		return
	phase = Phase.RETURN
	return_time = 0.0
	boss.enter_return_phase()
	hint.hide()
	weapon.set_combat_enabled(false)
	effects.camera_feedback_enabled = false
	dialogue.start_dialogue(roar_dialogue)

func _on_boss_jump() -> void:
	# The boss owns camera shake during its combat loop.
	effects.camera_feedback_enabled = false

func request_boss_skip() -> bool:
	if phase >= Phase.BOSS:
		return false
	completion.call("_dismiss_elite_lesson")
	get_tree().paused = false
	skip_requested = true
	return true


func prepare_scene_jump() -> void:
	# Prevent delayed dialogue/combat callbacks from starting another tutorial step.
	phase = Phase.FINISHED
	skip_requested = false
	completion.call("_stop_combat")
	dialogue.close_dialogue()
	set_process(false)

func skip_to_boss() -> void:
	if phase >= Phase.BOSS:
		return
	phase = Phase.BOSS
	player.heal_full()
	return_approach_started = true
	horde.active = false
	horde.spawning = false
	horde.opening_pending = false
	horde.opening_entering = false
	horde.opening_targets.clear()
	for enemy: Minotaur in horde.alive:
		if is_instance_valid(enemy):
			enemy.queue_free()
	horde.alive.clear()
	dialogue.close_dialogue()
	hint.hide()
	player.position = boss.intro_destination
	player.velocity = Vector2.ZERO
	player.intro_locked = true
	player.reset_physics_interpolation()
	boss.camera.reset_smoothing()
	weapon.reveal()
	weapon.set_combat_enabled(true)
	boss._start_from_throne()

func _on_boss_impact(_impact_position: Vector2) -> void:
	if phase != Phase.BOSS or elite_horde_started:
		return
	elite_horde_started = true
	horde.start_elite_horde()


