extends Node2D
## Proximity opens the lid and reveals the cards above the machine.

signal interacted
signal opened

const CLOSED: Texture2D = preload("res://assets/tiles/structures/booster_opener/closed1.png")
const OPENED: Texture2D = preload("res://assets/tiles/structures/booster_opener/opened.png")
const LIGHT_TEXTURE: Texture2D = preload("res://resources/visual/booster_opener_light.tres")

@export var player_path: NodePath
@export var interaction_enabled: bool = true
@export var action_prompt_enabled: bool = true
@export var click_interaction_enabled: bool = false
@export_range(32.0, 128.0, 1.0) var activation_radius: float = 68.0
@export_range(0.0, 32.0, 1.0) var proximity_hysteresis: float = 14.0
@export_range(0.3, 2.0, 0.05) var opening_duration: float = 1.05
@export_range(0.2, 2.0, 0.05) var lid_opening_duration: float = 0.65

var state: StringName = &"closed"
var open_amount: float = 0.0
var interaction_count: int = 0
var aperture_rect: Rect2i = Rect2i()
var aperture_center: Vector2 = Vector2.ZERO
var _player: Player = null
var _nearby: bool = false
var _elapsed: float = 0.0
var _interaction_pulse: float = 0.0
var _transition: Tween = null
var _pulse_tween: Tween = null
var _cards: Array[Sprite2D] = []
var _lid_amount: float = 0.0
var _on_platform: bool = false
var _platform_anchor: Vector2 = Vector2.ZERO
var _presented: bool = true
var _awaiting_clearance: bool = false
var _appearance: Tween = null
var _core_light: PointLight2D = null
var _rim_light: PointLight2D = null
static var _open_sprite_bounds: Rect2

@onready var _visuals: Node2D = $Visuals
@onready var _surface: AnimatedSprite2D = $Visuals/Surface
@onready var _aperture: Sprite2D = $Visuals/ApertureGlow
@onready var _beam: Node2D = $Visuals/Beam
@onready var _ground: Node2D = $Visuals/GroundGlow
@onready var _action: Sprite2D = $ActionPrompt
@onready var _collider: CollisionShape2D = $Body/CollisionShape2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for child: Node in $Visuals/Cards.get_children():
		var card: Sprite2D = child as Sprite2D
		if card != null:
			_cards.append(card)
	_map_aperture()
	_build_local_lighting()
	_action.call("configure", aperture_center + Vector2(0, -65))
	if not player_path.is_empty():
		bind_player(get_node_or_null(player_path) as Player)
	_apply_visuals()


func _build_local_lighting() -> void:
	# Use the game's soft radial light instead of turning the whole prop emissive.
	_core_light = PointLight2D.new()
	_core_light.name = "OpeningLight"
	_core_light.texture = LIGHT_TEXTURE
	_core_light.texture_scale = 1.3
	_core_light.position = aperture_center
	_core_light.color = Color(0.3, 0.85, 1.0)
	_core_light.energy = 0.0
	_core_light.shadow_enabled = false
	_visuals.add_child(_core_light)
	_rim_light = PointLight2D.new()
	_rim_light.name = "RimLight"
	_rim_light.texture = LIGHT_TEXTURE
	_rim_light.texture_scale = 1.65
	_rim_light.position = Vector2(0, 5)
	_rim_light.color = Color(1.0, 0.06, 0.55)
	_rim_light.energy = 0.0
	_rim_light.shadow_enabled = false
	_visuals.add_child(_rim_light)
	var contact_shadow: Sprite2D = Sprite2D.new()
	contact_shadow.name = "ContactShadow"
	contact_shadow.texture = LIGHT_TEXTURE
	contact_shadow.position = Vector2(0, 13)
	contact_shadow.scale = Vector2(0.85, 0.22)
	contact_shadow.modulate = Color(0.035, 0.015, 0.045, 0.32)
	contact_shadow.z_index = -3
	var unshaded: CanvasItemMaterial = CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	contact_shadow.material = unshaded
	_visuals.add_child(contact_shadow)
	_beam.self_modulate.a = 0.78
	_ground.self_modulate.a = 0.4


func bind_player(subject: Player) -> void:
	_player = subject


func fit_on_platform(target_width: float, surface_anchor: Vector2, projected_height: float) -> void:
	var source: Image = CLOSED.get_image()
	if source.is_compressed():
		source.decompress()
	var bounds: Rect2i = source.get_used_rect()
	var source_origin: Vector2 = _surface.position - Vector2(source.get_size()) * 0.5
	_platform_anchor = source_origin + Rect2(bounds).get_center()
	scale = Vector2.ONE * target_width / maxf(float(bounds.size.x), 1.0)
	position = surface_anchor - _platform_anchor * scale
	# Project only the artwork onto the elevated surface. Physics stays on the
	# ground plane, like the player's collision capsule on the existing ramps.
	_visuals.position.y = -projected_height / absf(global_scale.y)
	_action.scale = Vector2.ONE / global_scale.abs()
	_action.call("configure", _visuals.position + aperture_center + Vector2(0, -65))
	_on_platform = true
	z_as_relative = false


func appear_on_platform() -> void:
	_presented = false
	_awaiting_clearance = true
	_collider.disabled = true
	var rest_position: Vector2 = _visuals.position
	_visuals.position.y += 8.0
	_visuals.modulate.a = 0.0
	_appearance = create_tween().set_parallel(true)
	_appearance.tween_property(_visuals, "position", rest_position, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_appearance.tween_property(_visuals, "modulate:a", 1.0, 0.22)
	_appearance.chain().tween_callback(_finish_appearance)


func _finish_appearance() -> void:
	_presented = true


func _physics_process(_delta: float) -> void:
	_update_platform_collision_and_depth()
	var available: bool = interaction_enabled and _presented and is_instance_valid(_player) and not _player.dead and not _player.intro_locked
	var radius: float = activation_radius + (proximity_hysteresis if _nearby else 0.0)
	var inside: bool = available and _player.surface_world_position().distance_to(_visuals.to_global(aperture_center)) <= radius
	if inside != _nearby:
		_nearby = inside
		_transition_to(inside)
	_action.call("set_available", inside and action_prompt_enabled and state == &"opened")


func _update_platform_collision_and_depth() -> void:
	if not _on_platform or not is_instance_valid(_player):
		return
	# Match the actor's depth even though the supporting platform is a floor layer.
	z_index = _player.z_index + (1 if _player.global_position.y < to_global(_platform_anchor).y else -1)
	if not _awaiting_clearance:
		return
	var rectangle: RectangleShape2D = _collider.shape as RectangleShape2D
	var padding: Vector2 = Vector2(5, 6) / _collider.global_scale.abs()
	var half_size: Vector2 = rectangle.size * 0.5 + padding
	var subject: Vector2 = _collider.to_local(_player.to_global(Vector2(0, 3)))
	if absf(subject.x) > half_size.x or absf(subject.y) > half_size.y:
		# Victory can happen while the player stands in the future footprint.
		# Let them leave before enabling the solid body instead of trapping them.
		_collider.set_deferred("disabled", false)
		_awaiting_clearance = false


func _process(delta: float) -> void:
	_elapsed += delta
	_apply_visuals()


func _player_available() -> bool:
	return is_instance_valid(_player) and not _player.dead and not _player.intro_locked and not _player.is_dashing()


func can_interact() -> bool:
	return (action_prompt_enabled or click_interaction_enabled) and interaction_enabled and _nearby and state == &"opened" and _player_available()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or (key.physical_keycode != KEY_E and key.keycode != KEY_E):
		return
	if action_prompt_enabled and can_interact():
		get_viewport().set_input_as_handled()
		interact()


func _unhandled_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if not click_interaction_enabled or click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if can_interact() and _is_over_open_sprite(click.position):
		get_viewport().set_input_as_handled()
		interact()


func _is_over_open_sprite(viewport_point: Vector2) -> bool:
	if not _open_sprite_bounds.has_area():
		var image: Image = OPENED.get_image()
		if image.is_compressed():
			image.decompress()
		_open_sprite_bounds = Rect2(image.get_used_rect())
	var surface_bounds: Rect2 = _open_sprite_bounds
	surface_bounds.position += _surface.offset
	if _surface.centered:
		surface_bounds.position -= OPENED.get_size() * 0.5
	if surface_bounds.has_point(_surface.get_global_transform_with_canvas().affine_inverse() * viewport_point):
		return true
	for card: Sprite2D in _cards:
		if card.is_visible_in_tree() and card.get_rect().has_point(card.get_global_transform_with_canvas().affine_inverse() * viewport_point):
			return true
	return false


func interact() -> void:
	if not can_interact():
		return
	interaction_count += 1
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_interaction_pulse = 1.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "_interaction_pulse", 0.0, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	interacted.emit()


func reset_preview() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_nearby = false
	state = &"closed"
	open_amount = 0.0
	_lid_amount = 0.0
	_interaction_pulse = 0.0
	interaction_count = 0
	_elapsed = 0.0
	_action.call("set_available", false)
	_apply_visuals()


func _transition_to(should_open: bool) -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	state = &"opening" if should_open else &"closing"
	var target: float = 1.0 if should_open else 0.0
	var duration: float = (opening_duration if should_open else 0.62) * absf(target - open_amount)
	var lid_duration: float = (lid_opening_duration if should_open else 0.62) * absf(target - _lid_amount)
	_transition = create_tween().set_parallel(true)
	_transition.tween_property(self, "open_amount", target, maxf(duration, 0.08))
	_transition.tween_property(self, "_lid_amount", target, maxf(lid_duration, 0.08))
	_transition.chain().tween_callback(_finish_transition.bind(should_open))


func _finish_transition(is_open: bool) -> void:
	state = &"opened" if is_open else &"closed"
	open_amount = 1.0 if is_open else 0.0
	_lid_amount = open_amount
	_apply_visuals()
	if is_open:
		opened.emit()


func _apply_visuals() -> void:
	if state == &"closed" or state == &"opened":
		_surface.animation = state
		_surface.frame = 0
	else:
		_surface.animation = &"opening"
		_surface.frame = mini(floori(_lid_amount * 5.0), 4)
	# Sprite timing is independent; the generated light and card timing stays intact.
	var energy: float = smoothstep(0.73, 1.0, open_amount)
	var aperture_material: ShaderMaterial = _aperture.material as ShaderMaterial
	aperture_material.set_shader_parameter("energy", energy * 0.82)
	aperture_material.set_shader_parameter("pulse", _interaction_pulse)
	aperture_material.set_shader_parameter("elapsed", _elapsed)
	_aperture.visible = energy > 0.001
	_beam.call("set_energy", energy, _interaction_pulse, _elapsed)
	_ground.call("set_energy", energy, _interaction_pulse, _elapsed)
	_core_light.energy = energy * (0.18 + _interaction_pulse * 0.06)
	_rim_light.energy = (0.025 + energy * 0.02) if interaction_enabled else 0.0
	var tick: float = floorf(_elapsed * 12.0) / 12.0
	for index: int in range(_cards.size()):
		var card: Sprite2D = _cards[index]
		# Center card first, then the flanking cards, all from the mapped opening.
		var stagger: float = 0.0 if index == 1 else (0.045 if index == 0 else 0.09)
		var reveal: float = smoothstep(0.76 + stagger, 1.0, open_amount)
		var side: float = float(index - 1)
		var rest: Vector2 = Vector2(side * 18.0, -37.0 if index == 1 else -30.0)
		var bob: Vector2 = Vector2(sin(tick * 1.3 + float(index) * 1.7), sin(tick * 2.1 + float(index) * 1.9) * 2.0)
		var lift: Vector2 = Vector2(side * 3.0, -5.0) * _interaction_pulse
		card.position = (aperture_center + (rest + bob + lift) * reveal).round()
		card.rotation = side * 0.13 * reveal
		card.scale = Vector2.ONE * lerpf(0.5, 1.25, reveal)
		card.modulate = Color(1.0, 1.0, 1.0, reveal)
		card.visible = reveal > 0.01


func _map_aperture() -> void:
	# opened.png deliberately leaves its central slit transparent. The pixels that
	# were opaque in closed1 are the exact light mask, without repainting the art.
	var closed_image: Image = CLOSED.get_image()
	var open_image: Image = OPENED.get_image()
	if closed_image.is_compressed():
		closed_image.decompress()
	if open_image.is_compressed():
		open_image.decompress()
	var mask: Image = Image.create(open_image.get_width(), open_image.get_height(), false, Image.FORMAT_RGBA8)
	mask.fill(Color.TRANSPARENT)
	var low: Vector2i = open_image.get_size()
	var high: Vector2i = Vector2i(-1, -1)
	var search: Rect2i = Rect2i(32, 7, 64, 20)
	for y: int in range(search.position.y, search.end.y):
		for x: int in range(search.position.x, search.end.x):
			if closed_image.get_pixel(x, y).a > 0.9 and open_image.get_pixel(x, y).a < 0.1:
				mask.set_pixel(x, y, Color.WHITE)
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	if high.x < low.x:
		push_error("Booster opener: no central aperture was found in the authored frames.")
		return
	aperture_rect = Rect2i(low, high - low + Vector2i.ONE)
	aperture_center = (_surface.position - Vector2(open_image.get_size()) * 0.5 + Rect2(aperture_rect).get_center()).round()
	_aperture.texture = ImageTexture.create_from_image(mask)
	_aperture.position = _surface.position
	# Each instance owns its shader values, so one altar cannot light another.
	_aperture.material = _aperture.material.duplicate() as ShaderMaterial
	_beam.position = aperture_center
	_beam.call("configure", float(aperture_rect.size.x))
	_ground.call("configure", float(aperture_rect.size.x))
