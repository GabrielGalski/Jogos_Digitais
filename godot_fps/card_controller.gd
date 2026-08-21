extends Node

signal card_selected(index: int, card_name: String)
signal card_activated(index: int, card_name: String)

enum CardType {
	RIFLE,
	SHOTGUN,
	KATANA,
}

const CARD_NAMES: Array[String] = ["RIFLE", "SHOTGUN", "KATANA"]
const CROSSHAIRS: Array[Texture2D] = [
	preload("res://sprites/crosshair_rifle.png"),
	preload("res://sprites/crosshair_shotgun.png"),
	preload("res://sprites/crosshair_melee.png"),
]
const RIFLE_SHOT: AudioStream = preload("res://sfx/rifle_shot.mp3")
const SHOTGUN_SHOT: AudioStream = preload("res://sfx/shotgun_shot.wav")
const SHOTGUN_PUMP: AudioStream = preload("res://sfx/shotgun_pump.wav")
const KATANA_SLICES: Array[AudioStream] = [
	preload("res://sfx/katana_slice_1.wav"),
	preload("res://sfx/katana_slice_2.wav"),
]

const RIFLE_INTERVAL := 0.085
const SHOTGUN_INTERVAL := 0.82
const SHOTGUN_PUMP_DELAY := 0.34
const KATANA_INTERVAL := 0.34
const SHOTGUN_PELLETS := 9
const SHOTGUN_SPREAD := 0.085
const MAX_HITSCAN_DISTANCE := 45.0

@onready var player := get_parent() as CharacterBody3D
@onready var camera: Camera3D = player.get_node("ViewPivot/CameraTilt/CameraEffects/Camera3D")

var selected_card := CardType.RIFLE
var cooldowns: Array[float] = [0.0, 0.0, 0.0]
var activation_counts: Array[int] = [0, 0, 0]
var shotgun_pump_time := -1.0
var katana_sound_index := 0
var last_katana_sound_played := -1
var katana_swing_direction := 1.0
var card_panels: Array[PanelContainer] = []
var crosshair: TextureRect
var normal_card_style: StyleBoxFlat
var selected_card_style: StyleBoxFlat
var rifle_audio: AudioStreamPlayer
var shotgun_shot_audio: AudioStreamPlayer
var shotgun_pump_audio: AudioStreamPlayer
var katana_audio_players: Array[AudioStreamPlayer] = []
var random := RandomNumberGenerator.new()


func _ready() -> void:
	random.randomize()
	_build_audio_players()
	_build_hud()
	_update_selected_card()


func _process(delta: float) -> void:
	for index in cooldowns.size():
		cooldowns[index] = maxf(cooldowns[index] - delta, 0.0)

	if shotgun_pump_time >= 0.0:
		shotgun_pump_time -= delta
		if shotgun_pump_time <= 0.0:
			shotgun_pump_time = -1.0
			shotgun_pump_audio.play()

	if (
		selected_card == CardType.RIFLE
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	):
		activate_selected_card()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			select_relative(-1)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			select_relative(1)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				activate_selected_card()


func select_relative(direction: int) -> void:
	selected_card = posmod(selected_card + direction, CARD_NAMES.size())
	_update_selected_card()


func select_card(index: int) -> void:
	selected_card = clampi(index, 0, CARD_NAMES.size() - 1)
	_update_selected_card()


func activate_selected_card() -> bool:
	if cooldowns[selected_card] > 0.0:
		return false

	match selected_card:
		CardType.RIFLE:
			_fire_rifle()
		CardType.SHOTGUN:
			_fire_shotgun()
		CardType.KATANA:
			_swing_katana()

	activation_counts[selected_card] += 1
	card_activated.emit(selected_card, CARD_NAMES[selected_card])
	return true


func _fire_rifle() -> void:
	cooldowns[CardType.RIFLE] = RIFLE_INTERVAL
	rifle_audio.play()
	var direction := -camera.global_transform.basis.z.normalized()
	_fire_hitscan(direction, Color(0.45, 0.9, 1.0, 1.0), 0.026, 0.085)


func _fire_shotgun() -> void:
	cooldowns[CardType.SHOTGUN] = SHOTGUN_INTERVAL
	shotgun_pump_time = SHOTGUN_PUMP_DELAY
	shotgun_shot_audio.play()

	var basis := camera.global_transform.basis
	var forward := -basis.z.normalized()
	for _pellet in SHOTGUN_PELLETS:
		var direction := (
			forward
			+ basis.x * random.randf_range(-SHOTGUN_SPREAD, SHOTGUN_SPREAD)
			+ basis.y * random.randf_range(-SHOTGUN_SPREAD, SHOTGUN_SPREAD)
		).normalized()
		_fire_hitscan(direction, Color(1.0, 0.58, 0.18, 1.0), 0.018, 0.11)


func _swing_katana() -> void:
	cooldowns[CardType.KATANA] = KATANA_INTERVAL
	last_katana_sound_played = katana_sound_index
	katana_audio_players[katana_sound_index].play()
	katana_sound_index = (katana_sound_index + 1) % KATANA_SLICES.size()
	_spawn_katana_trail(katana_swing_direction)
	katana_swing_direction *= -1.0


func _fire_hitscan(direction: Vector3, color: Color, width: float, lifetime: float) -> void:
	var start := camera.global_position + direction * 0.35
	var target := camera.global_position + direction * MAX_HITSCAN_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var end := target if hit.is_empty() else hit.position as Vector3
	_spawn_tracer(start, end, color, width, lifetime)
	if not hit.is_empty():
		_spawn_impact(end, color, width * 3.2, lifetime * 1.6)


func _spawn_tracer(start: Vector3, end: Vector3, color: Color, width: float, lifetime: float) -> void:
	var distance := start.distance_to(end)
	if distance <= 0.01:
		return

	var material := _create_vfx_material(color, BaseMaterial3D.BLEND_MODE_ADD)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, distance)
	mesh.material = material
	var tracer := MeshInstance3D.new()
	tracer.name = "CardTracer"
	tracer.mesh = mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(tracer)
	tracer.global_position = (start + end) * 0.5
	tracer.look_at(end, Vector3.UP)

	var tween := create_tween()
	tween.tween_property(material, "albedo_color", Color(color.r, color.g, color.b, 0.0), lifetime)
	tween.finished.connect(tracer.queue_free)


func _spawn_impact(position: Vector3, color: Color, size: float, lifetime: float) -> void:
	var material := _create_vfx_material(color, BaseMaterial3D.BLEND_MODE_ADD)
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.material = material
	var impact := MeshInstance3D.new()
	impact.name = "CardImpact"
	impact.mesh = mesh
	impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(impact)
	impact.global_position = position

	var tween := create_tween().set_parallel(true)
	tween.tween_property(impact, "scale", Vector3.ONE * 2.4, lifetime)
	tween.tween_property(material, "albedo_color", Color(color.r, color.g, color.b, 0.0), lifetime)
	tween.finished.connect(impact.queue_free)


func _spawn_katana_trail(direction: float) -> void:
	var trail_root := Node3D.new()
	trail_root.name = "KatanaGlowTrail"
	camera.add_child(trail_root)

	var halo_color := Color(1.0, 0.28, 0.025, 0.42)
	var core_color := Color(1.0, 0.9, 0.48, 0.98)
	var halo_material := _create_vfx_material(halo_color, BaseMaterial3D.BLEND_MODE_ADD)
	var core_material := _create_vfx_material(core_color, BaseMaterial3D.BLEND_MODE_ADD)
	var halo := MeshInstance3D.new()
	var core := MeshInstance3D.new()
	halo.mesh = _create_arc_mesh(0.19, halo_material, direction)
	core.mesh = _create_arc_mesh(0.055, core_material, direction)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail_root.add_child(halo)
	trail_root.add_child(core)
	trail_root.rotation.z = deg_to_rad(4.0 * direction)
	trail_root.scale = Vector3(0.25, 0.8, 1.0)

	var reveal := create_tween()
	reveal.tween_property(trail_root, "scale", Vector3.ONE, 0.055)
	var fade := create_tween().set_parallel(true)
	fade.tween_property(halo_material, "albedo_color", Color(halo_color.r, halo_color.g, halo_color.b, 0.0), 0.15).set_delay(0.045)
	fade.tween_property(core_material, "albedo_color", Color(core_color.r, core_color.g, core_color.b, 0.0), 0.13).set_delay(0.045)
	fade.finished.connect(trail_root.queue_free)


func _create_arc_mesh(width: float, material: Material, direction: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	var segments := 24
	for index in range(segments + 1):
		var progress := float(index) / float(segments)
		var directed_progress := progress if direction > 0.0 else 1.0 - progress
		var angle := lerpf(-1.18, 1.18, directed_progress)
		var center := Vector3(
			sin(angle) * 1.08,
			-0.25 + cos(angle) * 0.16 + (progress - 0.5) * 0.08 * direction,
			-1.15 + cos(angle) * 0.06
		)
		var half_width := Vector3(0.0, width * 0.5, 0.0)
		mesh.surface_set_uv(Vector2(progress, 0.0))
		mesh.surface_add_vertex(center - half_width)
		mesh.surface_set_uv(Vector2(progress, 1.0))
		mesh.surface_add_vertex(center + half_width)
	mesh.surface_end()
	return mesh


func _create_vfx_material(color: Color, blend_mode: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.blend_mode = blend_mode
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 3.0
	return material


func _build_audio_players() -> void:
	rifle_audio = _create_audio_player("RifleAudio", RIFLE_SHOT, -8.0, 8)
	shotgun_shot_audio = _create_audio_player("ShotgunShotAudio", SHOTGUN_SHOT, -5.0, 2)
	shotgun_pump_audio = _create_audio_player("ShotgunPumpAudio", SHOTGUN_PUMP, -7.0, 2)
	for index in KATANA_SLICES.size():
		var audio := _create_audio_player("KatanaAudio%d" % (index + 1), KATANA_SLICES[index], -5.0, 2)
		katana_audio_players.append(audio)


func _create_audio_player(node_name: String, stream: AudioStream, volume_db: float, polyphony: int) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.name = node_name
	audio.stream = stream
	audio.volume_db = volume_db
	audio.max_polyphony = polyphony
	add_child(audio)
	return audio


func _build_hud() -> void:
	normal_card_style = _create_card_style(Color(0.08, 0.09, 0.12), 2)
	selected_card_style = _create_card_style(Color(0.2, 0.75, 1.0), 5)

	var hud := CanvasLayer.new()
	hud.name = "CardHUD"
	add_child(hud)
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	var hand := HBoxContainer.new()
	hand.name = "CardHand"
	hand.anchor_left = 1.0
	hand.anchor_right = 1.0
	hand.offset_left = -456.0
	hand.offset_top = 24.0
	hand.offset_right = -24.0
	hand.offset_bottom = 172.0
	hand.add_theme_constant_override("separation", 14)
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hand)

	for card_name in CARD_NAMES:
		var panel := PanelContainer.new()
		panel.name = "Card%s" % card_name.capitalize()
		panel.custom_minimum_size = Vector2(130.0, 148.0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.text = card_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.035, 0.04, 0.055))
		label.add_theme_font_size_override("font_size", 21)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)
		hand.add_child(panel)
		card_panels.append(panel)

	crosshair = TextureRect.new()
	crosshair.name = "Crosshair"
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -30.0
	crosshair.offset_top = -30.0
	crosshair.offset_right = 30.0
	crosshair.offset_bottom = 30.0
	crosshair.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crosshair.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crosshair.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)


func _create_card_style(border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10.0
	style.content_margin_top = 10.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 6
	return style


func _update_selected_card() -> void:
	if card_panels.is_empty() or crosshair == null:
		return
	for index in card_panels.size():
		var style := selected_card_style if index == selected_card else normal_card_style
		card_panels[index].add_theme_stylebox_override("panel", style)
		card_panels[index].modulate = Color.WHITE
	crosshair.texture = CROSSHAIRS[selected_card]
	card_selected.emit(selected_card, CARD_NAMES[selected_card])
