extends CanvasLayer
## Completes the encounter once and owns its health display and ending.
signal lesson_dismissed(lesson_id: StringName)

const ELITE_LESSON_DELAY: float = 0.5
const REWARD_TOAST: PackedScene = preload("res://scenes/visual/booster_reward_toast.tscn")
const MERCHANT_HALL: String = "res://scenes/merchant_corridor.tscn"
const ELITE_LESSON_COPY := "ASTERION É UM ELITE\n\nElites fortalecem os inimigos da câmara.\nDerrote o Elite para encerrar o combate."
const CONTROLS_LESSON_COPY := "COMANDOS\n\nWASD · Mover\nEspaço · Dash\nMouse · Mirar\nClique esquerdo · Atirar"
const TUTORIAL_REWARDS: Array[String] = [
	"Monster Booster vol. 1",
	"Monster Booster vol. 2",
	"Monster Booster vol. 3",
	"Pack de cartas",
]

var encounter: Node
var boss: Node
var player: Player
var arena: Node
var rewards_granted: bool = false
var rewards: Dictionary = {}
var completed: bool = false
var active_lesson: StringName = &""
@onready var nox_bar: Range = $Nox/HP
@onready var boss_panel: Control = $Boss
@onready var boss_bar: Range = $Boss/HP
@onready var end_screen: ColorRect = $Ending
@onready var end_text: Label = $Ending/Text
@onready var elite_modal: Control = $EliteLesson
@onready var lesson_text: Label = $EliteLesson/Panel/Content/Margin/Text
@onready var elite_ok: Button = $EliteLesson/Panel/Content/Ok
@onready var stair_direction: Control = $StairDirection

func setup(owner_encounter: Node) -> void:
	encounter = owner_encounter
	boss = encounter.boss
	player = encounter.player
	arena = boss.arena
	player.health_changed.connect(_nox_health)
	player.defeated.connect(_on_player_defeated)
	boss.health_changed.connect(_boss_health)
	boss.defeated.connect(_on_boss_defeated)
	boss.defeat_animation_finished.connect(_begin_surrender)
	boss.impact_started.connect(_explain_elite)
	encounter.dialogue.dialogue_finished.connect(_on_dialogue_finished)
	arena.tutorial_exited.connect(_on_exit)
	elite_ok.pressed.connect(_dismiss_elite_lesson)
	_nox_health(player.health, player.max_health)
	_boss_health(boss.health, boss.max_resistance)

func _process(_delta: float) -> void:
	if encounter != null:
		boss_panel.visible = encounter.phase == encounter.Phase.BOSS or (encounter.phase == encounter.Phase.VICTORY and not rewards_granted)

func _explain_elite(_point: Vector2) -> void:
	if encounter.phase == encounter.Phase.BOSS and not has_meta(&"elite_explained"):
		set_meta(&"elite_explained", true)
		await get_tree().create_timer(ELITE_LESSON_DELAY).timeout
		if encounter.phase == encounter.Phase.BOSS and not completed:
			_show_lesson(&"elite", ELITE_LESSON_COPY)


func show_controls_lesson() -> void:
	if has_meta(&"controls_explained"):
		lesson_dismissed.emit(&"controls")
		return
	set_meta(&"controls_explained", true)
	_show_lesson(&"controls", CONTROLS_LESSON_COPY)


func _show_lesson(lesson_id: StringName, message: String) -> void:
	active_lesson = lesson_id
	lesson_text.text = message
	elite_modal.show()
	get_tree().paused = true

func _dismiss_elite_lesson() -> void:
	if not elite_modal.visible:
		return
	var dismissed_lesson := active_lesson
	active_lesson = &""
	elite_modal.hide()
	get_tree().paused = false
	lesson_dismissed.emit(dismissed_lesson)

func _nox_health(current: float, maximum: float) -> void:
	nox_bar.max_value = maximum
	nox_bar.value = current

func _boss_health(current: float, maximum: float) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current

func _stop_combat() -> void:
	if elite_modal.visible:
		elite_modal.hide()
	active_lesson = &""
	get_tree().paused = false
	encounter.weapon.set_combat_enabled(false)
	encounter.horde.finish_chamber()
	encounter.effects.reset_random_seed()
	encounter.effects.camera_feedback_enabled = false
	for attack: Node in get_tree().get_nodes_in_group(&"minotaur_melee_attacks"):
		attack.queue_free()
	for shot: Node in get_tree().get_nodes_in_group(&"player_projectiles"):
		shot.queue_free()
	encounter.hint.hide()

func _on_boss_defeated() -> void:
	if player.dead or encounter.phase != encounter.Phase.BOSS:
		return
	encounter.phase = encounter.Phase.VICTORY
	_stop_combat()
	player.intro_locked = true
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.body.play(&"idle")

func _begin_surrender() -> void:
	if encounter.phase != encounter.Phase.VICTORY:
		return
	var sequence: DialogueSequence = DialogueSequence.new()
	sequence.sequence_id = &"asterion_surrender"
	var speakers: Array[String] = ["ASTERION", "NOX", "ASTERION", "ASTERION", "NOX", "ASTERION", "NOX", "ASTERION"]
	var texts: Array[String] = [
		"ESPERA! Eu me rendo! Não precisa me matar!",
		"⌁◌⋏∿ ⊙⋮⟐ ◊◎ ∿⌁◍ ⧜⋮○",
		"“As cartas.” Claro. Direto ao assunto.",
		"Eu entrego a coleção que trouxe. Estas cartas e três pacotes. Um de cada coleção inicial. E você me deixa vivo.",
		"◌",
		"Fechado? Sem revanche agora, sem levar o trono e sem contar que eu pedi por favor?",
		"∿",
		"A parte de não contar você não promete. Entendi.",
	]
	for index: int in range(texts.size()):
		var line: DialogueLine = DialogueLine.new()
		var speaker: DialogueSpeaker = DialogueSpeaker.new()
		speaker.display_name = speakers[index]
		line.speaker = speaker
		line.text = texts[index]
		sequence.lines.append(line)
	encounter.dialogue.start_dialogue(sequence)

func _on_dialogue_finished(sequence_id: StringName) -> void:
	if sequence_id != &"asterion_surrender" or encounter.phase != encounter.Phase.VICTORY or rewards_granted:
		return
	rewards_granted = true
	# Packs stay unopened; their card tutorial belongs to the next chamber.
	rewards = {"cards": ["CARD_MAN_001", "CARD_INF_001"], "packs": [
		{"set": 1, "unopened": true, "guaranteed_last_slot": "common_mutation"},
		{"set": 2, "unopened": true}, {"set": 3, "unopened": true}]}
	player.set_meta(&"tutorial_rewards", rewards)
	player.intro_locked = true
	await _present_rewards()
	player.intro_locked = false
	encounter.weapon.set_cutscene_pose(false)
	arena.restore_stair()
	stair_direction.call(&"point_to", arena.stair, player)


func _present_rewards() -> void:
	for reward_name: String in TUTORIAL_REWARDS:
		if not is_instance_valid(boss.actor):
			return
		var toast := REWARD_TOAST.instantiate() as Node2D
		arena.add_child(toast)
		toast.call(&"play", boss.actor.global_position + Vector2(0.0, -28.0), reward_name)
		await toast.tree_exited
		await get_tree().create_timer(0.06).timeout

func _on_player_defeated() -> void:
	encounter.phase = encounter.Phase.LOST
	_stop_combat()
	boss.set_physics_process(false)
	boss.actor.velocity = Vector2.ZERO
	boss._restore_camera()
	encounter.dialogue.close_dialogue()
	stair_direction.call(&"clear")
	end_text.text = "Nox foi derrotado.\nRecomeçando…"
	end_screen.show()
	await get_tree().create_timer(1.5).timeout
	get_tree().reload_current_scene()

func _on_exit() -> void:
	if completed:
		return
	completed = true
	encounter.phase = encounter.Phase.FINISHED
	_stop_combat()
	encounter.dialogue.close_dialogue()
	boss.set_physics_process(false)
	player.intro_locked = true
	player.velocity = Vector2.ZERO
	encounter.hint.hide()
	stair_direction.call(&"clear")
	end_text.text = ""
	end_screen.modulate.a = 0.0
	end_screen.show()
	var departure: Tween = create_tween()
	departure.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	departure.tween_property(end_screen, "modulate:a", 1.0, 0.6)
	await departure.finished
	get_tree().change_scene_to_file(MERCHANT_HALL)


func skip_to_merchant() -> void:
	_on_exit()
