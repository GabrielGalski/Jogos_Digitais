extends "res://scripts/visual/arena_lighting_rig.gd"
## Adapter only: no ownership of combat, camera, health or tutorial progress.
const BOSS_SCRIPT: Script = preload("res://scripts/asterion_skybreaker.gd")
const CLOUD_SHADER: Shader = preload("res://shaders/cloud_unshaded.gdshader")
const ENCOUNTER_SCRIPT: Script = preload("res://scripts/tutorial_encounter.gd")
var boss: Node2D
var encounter: Node
var target_glow: bool = false
var locked_target: bool = false
var victory_time: float = 0.0

func _ready() -> void:
	# Bind to actual collision geometry so moving/resizing a crater also moves its light.
	crater_regions.clear()
	for boundary_name: String in ["LargeHoleBoundary", "SmallHoleBoundary"]:
		var boundary: CollisionPolygon2D = get_parent().get_node_or_null("ArenaCollision/" + boundary_name) as CollisionPolygon2D
		if boundary == null or boundary.polygon.is_empty():
			continue
		var bounds: Rect2 = Rect2(to_local(boundary.to_global(boundary.polygon[0])), Vector2.ZERO)
		for point: Vector2 in boundary.polygon:
			bounds = bounds.expand(to_local(boundary.to_global(point)))
		crater_regions.append(bounds)
	super._ready()
	_bind_encounter.call_deferred()
	var cloud_material: ShaderMaterial = ShaderMaterial.new()
	cloud_material.shader = CLOUD_SHADER
	for cloud_path: String in ["FarClouds/CloudField", "NearClouds/CloudField"]:
		var cloud: Sprite2D = get_parent().get_node_or_null(cloud_path) as Sprite2D
		if cloud != null:
			cloud.material = cloud_material
			cloud.self_modulate = Color("#cab9d6") if cloud_path.begins_with("Near") else Color("#b7a8c4")

func _bind_encounter() -> void:
	boss = get_parent().get_node_or_null("MinotaurChair") as Node2D
	if boss == null:
		return
	encounter = boss.get_node("TutorialEncounter")
	boss.connect(&"skybreaker_started", _on_charge)
	boss.connect(&"launch_left_camera", _on_departure)
	boss.connect(&"target_locked", _on_target_locked)
	boss.connect(&"impact_started", _on_impact)
	boss.connect(&"skybreaker_finished", _on_land)
	boss.connect(&"defeated", _on_land)

func _process(delta: float) -> void:
	if is_instance_valid(boss) and is_instance_valid(encounter):
		var phase: int = int(encounter.get("phase"))
		var state: int = int(boss.get("state"))
		var actor: Node2D = boss.get("actor") as Node2D
		var dialogue: CanvasLayer = boss.get("dialogue_box") as CanvasLayer
		var talking: bool = dialogue != null and bool(dialogue.call(&"is_dialogue_active"))
		if state in [BOSS_SCRIPT.State.SKYBREAKER_PREPARE, BOSS_SCRIPT.State.THRONE_PROPULSION, BOSS_SCRIPT.State.LAUNCHING]:
			set_focus(0.55, 0.75, 1.25)
		elif state in [BOSS_SCRIPT.State.OFFSCREEN, BOSS_SCRIPT.State.DESCENDING]:
			set_focus(0.55, 0.75, 0.0)
		elif phase >= ENCOUNTER_SCRIPT.Phase.VICTORY:
			victory_time += delta
			set_focus(0.35, 0.20, 0.38 * exp(-victory_time * 1.2))
		elif phase in [ENCOUNTER_SCRIPT.Phase.HORDE, ENCOUNTER_SCRIPT.Phase.BOSS]:
			set_focus(0.75, 0.55, 0.60)
		elif talking:
			set_focus(0.25, 0.25, 1.0)
		else:
			set_focus(0.30, 0.35, 0.85)
		var on_throne: bool = state in [BOSS_SCRIPT.State.SITTING, BOSS_SCRIPT.State.PLAYER_APPROACH, BOSS_SCRIPT.State.THRONE_PAUSE, BOSS_SCRIPT.State.INTRO_DIALOGUE, BOSS_SCRIPT.State.WEAPON_REVEAL, BOSS_SCRIPT.State.HORDE, BOSS_SCRIPT.State.WAIT_RETURN]
		if actor != null and not on_throne:
			boss_light.global_position = actor.global_position + Vector2(0, -22)
		else:
			boss_light.global_position = boss.global_position + Vector2(0, -25)
		if target_glow:
			if not locked_target:
				impact_light.global_position = boss.get("impact_position") as Vector2
			impact_remaining = profile.impact_duration * 0.18
	super._process(delta)

func _on_charge() -> void:
	target_glow = false
	locked_target = false

func _on_departure() -> void:
	target_glow = true
	boss_weight = 0.0

func _on_target_locked(at: Vector2) -> void:
	locked_target = true
	impact_light.global_position = at

func _on_impact(at: Vector2) -> void:
	target_glow = false
	flash_impact(at)

func _on_land() -> void:
	target_glow = false
