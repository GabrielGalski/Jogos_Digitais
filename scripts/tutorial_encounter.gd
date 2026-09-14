extends Node
## Owns the first conversation, weapon reveal, minion encounter and return to throne.
enum Phase { INTRO, REVEAL, ARMED_DIALOGUE, OPENING, HORDE, RETURN, CHALLENGE, BOSS }
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
@onready var horde: Node2D = $Horde
@onready var effects: CombatEffects = $Effects
@onready var projectiles: Node2D = $Projectiles
@onready var hint: Label = $HUD/SafeArea/Hint

func setup(owner_boss: Node2D, arena: Node2D, owner_player: Player, box: DialogueBox) -> void:
	boss = owner_boss
	player = owner_player
	dialogue = box
	weapon = player.get_node("BoosterShooter") as Node2D
	weapon.effects = effects
	weapon.projectiles = projectiles
	horde.setup(player, arena)
	horde.horde_cleared.connect(_on_horde_cleared)
	horde.opening_arrived.connect(_on_opening_arrived)
	effects.camera_feedback_enabled = false
	boss.skybreaker_started.connect(_on_boss_jump)
	boss.impact_started.connect(_on_boss_impact)
	hint.hide()

func begin_dialogue() -> void:
	if phase == Phase.RETURN:
		phase = Phase.CHALLENGE
		weapon.set_combat_enabled(false)
		weapon.set_cutscene_pose(true)
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
		weapon.set_cutscene_pose(true)
		horde.start_horde()
	elif phase == Phase.CHALLENGE and sequence_id == challenge_dialogue.sequence_id:
		phase = Phase.BOSS
		weapon.set_cutscene_pose(false)
		weapon.set_combat_enabled(true)
		boss._start_from_throne()

func _process(delta: float) -> void:
	if player == null:
		return
	if phase == Phase.REVEAL:
		reveal_time += delta
		if reveal_time >= weapon_reveal_duration:
			phase = Phase.ARMED_DIALOGUE
			boss.enter_intro_dialogue_state()
			weapon.set_cutscene_pose(true)
			dialogue.start_dialogue(armed_dialogue)
	elif phase == Phase.HORDE:
		hint.text = "WASD · Mover    Mouse · Mirar    Segure clique esquerdo · Atirar"
		if not horde.spawning:
			hint.hide()
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
	weapon.set_cutscene_pose(false)
	weapon.set_combat_enabled(true)
	effects.camera_feedback_enabled = true
	hint.show()

func _on_horde_cleared() -> void:
	phase = Phase.RETURN
	return_time = 0.0
	boss.enter_return_phase()
	hint.hide()
	weapon.set_combat_enabled(false)
	weapon.set_cutscene_pose(true)
	effects.camera_feedback_enabled = false
	dialogue.start_dialogue(roar_dialogue)

func _on_boss_jump() -> void:
	# The boss owns camera shake during its combat loop.
	effects.camera_feedback_enabled = false

func _on_boss_impact(_impact_position: Vector2) -> void:
	if phase != Phase.BOSS or elite_horde_started:
		return
	elite_horde_started = true
	horde.start_elite_horde()


