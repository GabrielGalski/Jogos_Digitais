extends Node2D
## Two fixed rooms in one world. Only the merchant boundary changes scenes.

const MERCHANT: String = "res://scenes/merchant_corridor.tscn"
enum Stage { ARRIVING, ENTRANCE, ROOM_ONE, CORRIDOR, ROOM_TWO, EXITS, FINISHED, RETURNING }
var stage: Stage = Stage.ARRIVING
var reveal: float = 0.0
var chosen_exit: int = 0
@onready var player: Player = $Nox
@onready var room_one: Node2D = $Room1Encounter
@onready var room_two: Node2D = $Room2Encounter
@onready var room_two_visual: Node2D = $Layout/Room2
@onready var status: Label = $HUD/Frame/Column/Status
@onready var hint: Label = $HUD/Frame/Column/Hint
@onready var fade: ColorRect = $HUD/Fade
@onready var gun: Node2D = $Nox/BoosterShooter
@onready var health_bar: Range = $HUD/Frame/Column/Health

func _ready() -> void:
	gun.set("effects", $Effects)
	gun.set("projectiles", $Projectiles)
	gun.set("projectile_obstacle_mask", 16)
	gun.call("reveal")
	gun.call("set_combat_enabled", true)
	room_one.connect("progress_changed", _update_status)
	room_two.connect("progress_changed", _update_status)
	room_one.connect("cleared", _room_one_cleared)
	room_two.connect("cleared", _room_two_cleared)
	player.health_changed.connect(_health_changed)
	player.defeated.connect(_on_defeated)
	_health_changed(player.health, player.max_health)
	var camera: Camera2D = $Nox/Camera2D
	camera.zoom = Vector2.ONE
	camera.position_smoothing_speed = 7.0
	camera.reset_smoothing()
	room_two_visual.modulate.a = 0.0
	$Layout/ExitDown.modulate.a = 0.0
	$Layout/ExitRight.modulate.a = 0.0
	_update_status()
	await _fade_to(0.0, 0.45)
	player.intro_locked = false
	stage = Stage.ENTRANCE
	_update_status()

func _physics_process(delta: float) -> void:
	if stage in [Stage.ARRIVING, Stage.FINISHED, Stage.RETURNING]:
		return
	var at: Vector2 = player.position
	if stage == Stage.ENTRANCE and at.x >= 20.0:
		stage = Stage.ROOM_ONE
		_set_gate("Room1/EntranceGate", true)
		room_one.call("begin", player)
	elif stage == Stage.CORRIDOR and at.y < -116.0 and at.x >= 400.0 and at.x <= 432.0:
		stage = Stage.ROOM_TWO
		_set_gate("Room2/EntranceGate", true)
		room_two.call("begin", player)
	elif stage == Stage.EXITS:
		if at.y > -24.0 and at.x > 656.0 and at.x < 688.0:
			_finish(1)
		elif at.x > 856.0 and at.y > -288.0 and at.y < -256.0:
			_finish(2)
	# Reveal persists once explored. No black screen, teleport or reload between rooms.
	if stage in [Stage.CORRIDOR, Stage.ROOM_TWO, Stage.EXITS]:
		var distance_to_entry: float = at.distance_to(Vector2(416, -96))
		var target: float = 1.0 - smoothstep(24.0, 184.0, distance_to_entry)
		if stage in [Stage.ROOM_TWO, Stage.EXITS]:
			target = 1.0
		reveal = move_toward(reveal, maxf(reveal, target), delta * 2.5)
		room_two_visual.modulate.a = reveal
		$Layout/ExitDown.modulate.a = reveal
		$Layout/ExitRight.modulate.a = reveal

func _set_gate(path: String, locked: bool) -> void:
	var gate: StaticBody2D = get_node("Layout/" + path) as StaticBody2D
	gate.set_deferred("collision_layer", 17 if locked else 0)

func _room_one_cleared() -> void:
	if stage != Stage.ROOM_ONE:
		return
	_set_gate("Room1/PassageGate", false)
	stage = Stage.CORRIDOR
	_update_status()

func _room_two_cleared() -> void:
	if stage != Stage.ROOM_TWO:
		return
	_set_gate("Room2/EntranceGate", false)
	_set_gate("Room2/ExitDownGate", false)
	_set_gate("Room2/ExitRightGate", false)
	stage = Stage.EXITS
	_update_status()

func _update_status() -> void:
	hint.text = "WASD: mover  |  Mouse: mirar / atirar  |  Shift: dash"
	match stage:
		Stage.ARRIVING, Stage.ENTRANCE:
			status.text = "ENTRADA  —  avance para a primeira sala"
		Stage.ROOM_ONE:
			status.text = "SALA 1  •  Minotauros: %d / 6" % int(room_one.get("defeated_count"))
			hint.text = "Entrada fechada. Derrote os 6 minotauros para abrir a passagem."
		Stage.CORRIDOR:
			status.text = "SALA 1 CONCLUÍDA"
			hint.text = "Passagem livre à direita. Siga o corredor e vire para cima."
		Stage.ROOM_TWO:
			status.text = "SALA 2  •  Minotauros: %d / 8" % int(room_two.get("defeated_count"))
			if int(room_two.get("phase")) == 4:
				hint.text = "Trigger de Elite atingido — Elite desativado neste teste."
			else:
				hint.text = "Leva %d / 2. As saídas abrem ao concluir o encontro." % (int(room_two.get("wave_index")) + 1)
		Stage.EXITS:
			status.text = "SALA 2 CONCLUÍDA  •  Saídas abertas"
			hint.text = "Escolha a passagem inferior ou a passagem à direita."

func _health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

func _finish(exit_number: int) -> void:
	if stage == Stage.FINISHED:
		return
	chosen_exit = exit_number
	stage = Stage.FINISHED
	player.intro_locked = true
	gun.call("set_combat_enabled", false)
	await _fade_to(0.9, 0.6)
	$HUD/Frame.hide()
	$HUD/Ending/Text.text = "TESTE CONCLUÍDO  •  SAÍDA %d\n\nR: voltar ao mercador" % chosen_exit
	$HUD/Ending.show()

func _on_defeated() -> void:
	if stage == Stage.RETURNING:
		return
	room_one.call("cancel")
	room_two.call("cancel")
	_return_to_merchant()

func _unhandled_key_input(event: InputEvent) -> void:
	if stage == Stage.FINISHED and event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_R:
			_return_to_merchant()

func _return_to_merchant() -> void:
	stage = Stage.RETURNING
	player.intro_locked = true
	gun.call("set_combat_enabled", false)
	await _fade_to(1.0, 0.45)
	get_tree().change_scene_to_file(MERCHANT)

func _fade_to(alpha: float, duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(fade, "color:a", alpha, duration)
	await tween.finished
