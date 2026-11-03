extends Node2D
## Shared original-player ranged combat and framing for tutorial and LDtk.

const RETICLE: Script = preload("res://scripts/dungeon/manifestation_reticle.gd")
const CAMERA_RIG: Script = preload("res://scripts/visual/gameplay_camera_rig.gd")
const DASH_SLIDES: Script = preload("res://scripts/visual/player_dash_slides.gd")
const ROLL_EFFECTS: Script = preload("res://scripts/visual/player_roll_effects.gd")
const PARRY: Script = preload("res://scripts/combat/player_parry.gd")
const PRESENTATION: PackedScene = preload("res://scenes/visual/training_projectile_style.tscn")
const TUTORIAL_M01: ManifestationCard = preload("res://resources/cards/preview/M01.tres")
const MANIFESTATIONS: Script = preload("res://scripts/combat/manifestations/manifestation_controller.gd")

var world_bounds: Rect2 = Rect2()
var gameplay: Node2D = null
var combat_enabled: bool = true
var procedural_weapons_enabled: bool = false
var reticle: Sprite2D = null
var shooter: Node2D = null
var effects: CombatEffects = null
var projectiles: Node2D = null
var _aim_layer: CanvasLayer = null
var _parry: Node2D = null
var _camera_rig: Node = null
@onready var player: Player = get_parent() as Player


func _ready() -> void:
	player.dash_afterimages_enabled = false
	var momentum: Node2D = player.get_node("MomentumLine") as Node2D
	momentum.hide()
	momentum.set_process(false)
	var slides: Node2D = DASH_SLIDES.new() as Node2D
	slides.name = "DashSlides"
	player.add_child(slides)
	var dust: Node2D = ROLL_EFFECTS.new() as Node2D
	dust.name = "RollEffects"
	player.add_child(dust)
	_parry = PARRY.new() as Node2D
	_parry.name = "Parry"
	_parry.set("combat_enabled", combat_enabled)
	player.add_child(_parry)
	effects = CombatEffects.new()
	effects.name = "ShooterEffects"
	effects.top_level = true
	effects.explosion_visuals_enabled = false
	effects.camera_feedback_enabled = false
	add_child(effects)
	projectiles = Node2D.new()
	projectiles.name = "PlayerProjectiles"
	player.get_parent().add_child(projectiles)
	var presentation: Node2D = null
	if not procedural_weapons_enabled:
		presentation = PRESENTATION.instantiate() as Node2D
		presentation.name = "ProjectileWorldStyle"
		player.get_parent().add_child(presentation)
	shooter = player.get_node("BoosterShooter") as Node2D
	shooter.set("effects", effects)
	shooter.set("projectiles", projectiles)
	shooter.set("projectile_presentation", presentation)
	shooter.set("use_m01_projectile", true)
	shooter.set("projectile_obstacle_mask", 1)
	var loadout: CardLoadout = (shooter.get("initial_loadout") as CardLoadout).duplicate(true) as CardLoadout
	loadout.manifestation = TUTORIAL_M01
	shooter.call("equip_cards", loadout)
	shooter.call("set_combat_enabled", combat_enabled)
	_aim_layer = CanvasLayer.new()
	_aim_layer.name = "ArenaUI"
	_aim_layer.layer = 90
	_aim_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	reticle = RETICLE.new() as Sprite2D
	reticle.name = "Crosshair"
	reticle.call("set_tint", Color.WHITE)
	_aim_layer.add_child(reticle)
	player.get_parent().add_child(_aim_layer)
	if procedural_weapons_enabled:
		var manifestations: Node = MANIFESTATIONS.new()
		manifestations.name = "Manifestations"
		add_child(manifestations)
		manifestations.call("configure", player, shooter, projectiles, reticle)
	_camera_rig = CAMERA_RIG.new()
	_camera_rig.name = "GameplayCameraRig"
	_camera_rig.set("player", player)
	_camera_rig.set("world_bounds", world_bounds)
	add_child(_camera_rig)
	_camera_rig.call("bind_effects", effects)


func _process(_delta: float) -> void:
	if is_instance_valid(shooter) and is_instance_valid(reticle):
		shooter.set("aim_screen_override", reticle.position)


func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	shooter.call("set_combat_enabled", enabled)
	_parry.set("combat_enabled", enabled)
	if not enabled:
		_parry.call("cancel")


func reveal() -> void:
	shooter.call("reveal")


func bind_effects(shared_effects: CombatEffects) -> void:
	# Tutorial owns the impact/reset lifecycle; LDtk keeps the local fallback.
	if effects != shared_effects:
		effects.queue_free()
		effects = shared_effects
		shooter.set("effects", effects)
		_camera_rig.call("bind_effects", effects)


func _exit_tree() -> void:
	if is_instance_valid(_aim_layer):
		_aim_layer.queue_free()
	if is_instance_valid(projectiles):
		projectiles.queue_free()
