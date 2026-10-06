extends Node
## Persistent M03 heat and damage clock; switching weapons cannot reset either.
const BURST: Script = preload("res://scripts/dungeon/banshee_burst.gd")
@export var heat_per_second: float = 25.0
@export var cooling_per_second: float = 50.0
@export var overheat_delay: float = 1.2

var heat: float = 0.0
var overheated: bool = false
var delay_remaining: float = 0.0
var hit_cooldown: float = 0.0
var active: bool = false
var state_text: String = "PRONTO"
var player: Player
var muzzle: Marker2D
var runtime: CardCombatRuntime
var effects: CombatEffects
var cursor_world: Callable
var visual: Node2D
var hud: ColorRect
var bar: ColorRect
var bar_offset_y: float = 18.0


func setup(nox: Player, source: Marker2D, cards: CardCombatRuntime, combat: CombatEffects, ui: Node, aim: Callable) -> void:
	player = nox
	muzzle = source
	runtime = cards
	effects = combat
	cursor_world = aim
	hud = ColorRect.new()
	hud.name = "BansheeHeat"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.color = Color("#25131a")
	hud.size = Vector2(24, 1)
	ui.add_child(hud)
	bar = ColorRect.new()
	bar.name = "Fill"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = Color("#b9f4ee")
	bar.size = Vector2(0, 1)
	hud.add_child(bar)
	var idle_frame: Texture2D = player.body.sprite_frames.get_frame_texture(&"idle", 0)
	if idle_frame != null:
		bar_offset_y = player.body.position.y + idle_frame.get_height() * absf(player.body.scale.y) * 0.5 + 3.0
	hud.hide()
	_refresh_hud()


func tick(delta: float, requested: bool, selected: bool) -> void:
	hit_cooldown = maxf(0.0, hit_cooldown - delta)
	active = false
	if overheated:
		var cooling_time: float = maxf(0.0, delta - delay_remaining)
		delay_remaining = maxf(0.0, delay_remaining - delta)
		if cooling_time > 0.0:
			heat = maxf(0.0, heat - cooling_per_second * cooling_time)
		if heat <= 0.0:
			overheated = false
		state_text = "SUPERAQUECIDO" if delay_remaining > 0.0 else "RESFRIANDO"
	elif requested:
		heat = minf(100.0, heat + heat_per_second * delta)
		if heat >= 100.0:
			overheated = true
			delay_remaining = overheat_delay
			state_text = "SUPERAQUECIDO"
		else:
			active = true
			state_text = "EM USO"
	else:
		heat = maxf(0.0, heat - cooling_per_second * delta)
		state_text = "RESFRIANDO" if heat > 0.0 else "PRONTO"
	if not overheated and heat <= 0.0 and not active:
		state_text = "PRONTO"
	if active:
		_start_visual()
		if is_instance_valid(visual):
			visual.call(&"follow_source")
			if hit_cooldown <= 0.0:
				var attack: CardAttack = runtime.create_attack()
				if attack != null:
					visual.call(&"apply_channel_hit", attack)
					hit_cooldown = attack.fire_interval
	else:
		_stop_visual()
	hud.visible = selected or heat > 0.0
	_refresh_hud()


func _start_visual() -> void:
	if is_instance_valid(visual):
		return
	var snapshot: CardAttack = runtime.create_attack()
	if snapshot == null:
		return
	visual = BURST.new() as Node2D
	player.get_parent().add_child(visual)
	visual.call(&"configure_channel", muzzle, cursor_world, snapshot, effects)


func _stop_visual() -> void:
	if is_instance_valid(visual):
		visual.hide()
		visual.queue_free()
	visual = null


func _process(_delta: float) -> void:
	if is_instance_valid(player) and is_instance_valid(hud):
		var anchor: Vector2 = player.get_global_transform_with_canvas().origin + Vector2(0, bar_offset_y * player.get_viewport().get_canvas_transform().get_scale().y)
		var bounds: Vector2 = player.get_viewport_rect().size
		hud.position = (anchor - Vector2(hud.size.x * 0.5, 0)).clamp(Vector2.ZERO, (bounds - hud.size).max(Vector2.ZERO)).round()


func _refresh_hud() -> void:
	var tint: Color = Color("#b9f4ee")
	if overheated:
		tint = Color("#ff6480") if delay_remaining > 0.0 else Color("#ffc477")
	elif heat >= 75.0:
		tint = Color("#ffc477")
	bar.size.x = roundf(hud.size.x * heat / 100.0)
	bar.color = tint


func _exit_tree() -> void:
	_stop_visual()
	if is_instance_valid(hud):
		hud.queue_free()
