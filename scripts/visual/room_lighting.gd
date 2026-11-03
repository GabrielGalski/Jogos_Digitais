extends CanvasLayer
## One world snapshot and grading pass below UI; the circle is measured in world pixels.

const VISIBILITY_SHADER: Shader = preload("res://shaders/room_visibility.gdshader")
const SETUP_SESSION_KEY: StringName = &"monster_booster_room_lighting_setup"
@export var profile: Resource
@export var setups: Resource
var subject: Node2D = null
var _overlay: ColorRect = null
var _world_snapshot: BackBufferCopy = null
var _material: ShaderMaterial = null
var _contact_shadow: Sprite2D = null
var _original_shadow: CanvasItem = null
var _original_shadow_visible: bool = false
var _previous_transform: Transform2D = Transform2D.IDENTITY
var _current_transform: Transform2D = Transform2D.IDENTITY
var _sampled_subject: bool = false
var _movement_target: float = 0.0
var _movement_weight: float = 0.0
var _breathing_phase: float = 0.0
var _setup_profiles: Array[Resource] = []
var _setup_index: int = -1
var _setup_hint: Label = null
var _hint_remaining: float = 0.0

signal setup_changed(index: int, label: String)


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Camera framing runs at priority 10. Upload the final canvas transform just before drawing.
	process_priority = 100
	process_physics_priority = 100
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world_snapshot = BackBufferCopy.new()
	_world_snapshot.name = "WorldSnapshot"
	_world_snapshot.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_world_snapshot)
	_overlay = ColorRect.new()
	_overlay.name = "WorldExposure"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = VISIBILITY_SHADER
	_overlay.material = _material
	add_child(_overlay)
	_build_setup_hint()
	if profile != null:
		profile.changed.connect(apply_profile)
	apply_profile()
	if setups != null:
		for candidate: Resource in setups.get("profiles"):
			if candidate != null:
				_setup_profiles.append(candidate)
		if not _setup_profiles.is_empty():
			if can_cycle_setups():
				add_to_group(&"room_lighting_setup_switchers")
			select_setup(int(get_tree().get_meta(SETUP_SESSION_KEY, int(setups.get("default_index")))))
	RenderingServer.frame_pre_draw.connect(update_frame)
	update_frame()
	_sample_subject(true)


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_sample_subject(false)
	_movement_target = 0.0
	if profile == null or not _sampled_subject or delta <= 0.0:
		return
	# Actual travel, rather than input: holding a key against a wall does not expand the light.
	# Teleports reset both samples; dash speed is clamped to the normal walking envelope.
	var speed: float = _previous_transform.origin.distance_to(_current_transform.origin) / delta
	var reference: float = maxf(float(profile.get("movement_reference_speed")), 1.0)
	_movement_target = clampf(speed / reference, 0.0, 1.0)


func _process(delta: float) -> void:
	if _setup_hint != null:
		_hint_remaining = maxf(_hint_remaining - delta, 0.0)
		_setup_hint.visible = _hint_remaining > 0.0
		_setup_hint.modulate.a = clampf(_hint_remaining / 0.35, 0.0, 1.0)
	if get_tree().paused:
		return
	if profile == null or _overlay == null or not _overlay.visible:
		return
	if bool(profile.get("breathing_enabled")):
		var time_constant: float = float(profile.get("expansion_time")) if _movement_target > _movement_weight else float(profile.get("contraction_time"))
		_movement_weight = lerpf(_movement_weight, _movement_target, 1.0 - exp(-delta / maxf(time_constant, 0.01)))
		var period: float = maxf(float(profile.get("breathing_period")), 0.1)
		_breathing_phase = fposmod(_breathing_phase + TAU * delta / period, TAU)
	_apply_radius()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or not can_cycle_setups():
		return
	if key.physical_keycode != KEY_BACKSPACE and key.keycode != KEY_BACKSPACE:
		return
	select_setup((_setup_index + 1) % _setup_profiles.size())
	get_viewport().set_input_as_handled()


func can_cycle_setups() -> bool:
	return setups != null and bool(setups.get("cycling_enabled")) and _setup_profiles.size() > 1


func setup_count() -> int:
	return _setup_profiles.size()


func setup_index() -> int:
	return _setup_index


func setup_name() -> String:
	return profile.resource_name if profile != null else ""


func select_setup(index: int) -> void:
	if _setup_profiles.is_empty():
		return
	_setup_index = clampi(index, 0, _setup_profiles.size() - 1)
	get_tree().set_meta(SETUP_SESSION_KEY, _setup_index)
	if profile != null and profile.changed.is_connected(apply_profile):
		profile.changed.disconnect(apply_profile)
	profile = _setup_profiles[_setup_index]
	profile.changed.connect(apply_profile)
	apply_profile()
	# Preserve breathing phase, movement envelope, camera, collision and the player's pose.
	if _setup_hint != null:
		_setup_hint.text = "%d/%d  %s" % [_setup_index + 1, _setup_profiles.size(), setup_name()]
		_hint_remaining = 2.6 if can_cycle_setups() else 0.0
		_setup_hint.visible = can_cycle_setups()
		_setup_hint.modulate.a = 1.0
	setup_changed.emit(_setup_index, setup_name())


func _build_setup_hint() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "SetupHintMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	add_child(margin)
	_setup_hint = Label.new()
	_setup_hint.name = "SetupHint"
	_setup_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_hint.add_theme_font_override("font", load("res://assets/font/determination.ttf") as Font)
	_setup_hint.add_theme_font_size_override("font_size", 12)
	_setup_hint.add_theme_color_override("font_color", Color("#d4bdcf"))
	_setup_hint.add_theme_color_override("font_shadow_color", Color(0.025, 0.01, 0.035, 0.9))
	_setup_hint.add_theme_constant_override("shadow_offset_x", 1)
	_setup_hint.add_theme_constant_override("shadow_offset_y", 1)
	_setup_hint.hide()
	margin.add_child(_setup_hint)


func _apply_radius() -> void:
	if _material == null or profile == null:
		return
	var radius: float = maxf(float(profile.get("radius")), 1.0)
	if bool(profile.get("breathing_enabled")):
		var resting: float = maxf(float(profile.get("idle_radius_ratio")), 0.1)
		var moving: float = maxf(float(profile.get("moving_radius_ratio")), resting)
		var amplitude: float = clampf(float(profile.get("breathing_amplitude")), 0.0, 0.15)
		radius *= lerpf(resting, moving, _movement_weight) * (1.0 + sin(_breathing_phase) * amplitude)
	_material.set_shader_parameter("radius", radius)


func _sample_subject(reset: bool) -> void:
	if not is_instance_valid(subject):
		_sampled_subject = false
		return
	_previous_transform = _current_transform
	_current_transform = subject.global_transform
	if reset or not _sampled_subject or _previous_transform.origin.distance_to(_current_transform.origin) > 32.0:
		_previous_transform = _current_transform
	_sampled_subject = true


func apply_profile() -> void:
	if _overlay == null:
		return
	_overlay.visible = profile != null and bool(profile.get("enabled"))
	_world_snapshot.visible = _overlay.visible
	_remove_contact_shadow()
	if not _overlay.visible:
		return
	_material.set_shader_parameter("ambient_multiplier", profile.get("ambient_multiplier"))
	_material.set_shader_parameter("center_multiplier", profile.get("center_multiplier"))
	_material.set_shader_parameter("saturation", maxf(float(profile.get("saturation")), 0.0))
	_apply_radius()
	_material.set_shader_parameter("clear_center_ratio", clampf(float(profile.get("clear_center_ratio")), 0.0, 0.95))
	_material.set_shader_parameter("pixel_size", maxf(float(profile.get("pixel_size")), 0.0))
	_material.set_shader_parameter("brightness_steps", int(profile.get("brightness_steps")))
	if is_instance_valid(subject) and bool(profile.get("contact_shadow_enabled")):
		_build_contact_shadow()


func update_frame() -> void:
	if _overlay == null or not _overlay.visible:
		return
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var size: Vector2 = get_viewport().get_visible_rect().size
	_material.set_shader_parameter("world_origin", inverse.origin)
	_material.set_shader_parameter("world_axis_x", inverse.basis_xform(Vector2(size.x, 0.0)))
	_material.set_shader_parameter("world_axis_y", inverse.basis_xform(Vector2(0.0, size.y)))
	var valid: bool = is_instance_valid(subject)
	_material.set_shader_parameter("has_subject", valid)
	if valid:
		var center_offset: Vector2 = profile.get("center_offset")
		if subject is Player:
			center_offset += (subject as Player).floor_visual_offset()
		# Node2D exposes no interpolated-global getter. Sample physics after the actor moves.
		var subject_transform: Transform2D = subject.global_transform
		if _sampled_subject and subject.physics_interpolation_mode != Node.PHYSICS_INTERPOLATION_MODE_OFF \
				and bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)):
			if _current_transform.origin.distance_to(subject_transform.origin) > 32.0:
				_sample_subject(true)
			subject_transform = _previous_transform.interpolate_with(_current_transform, Engine.get_physics_interpolation_fraction())
		_material.set_shader_parameter("center_world", subject_transform * center_offset)


func bind_subject(actor: Node2D) -> void:
	_remove_contact_shadow()
	subject = actor
	_movement_target = 0.0
	_movement_weight = 0.0
	_sample_subject(true)
	apply_profile()
	update_frame()


func _build_contact_shadow() -> void:
	_original_shadow = subject.get_node_or_null("GroundShadow") as CanvasItem
	if _original_shadow != null:
		_original_shadow_visible = _original_shadow.visible
		_original_shadow.hide()
	var gradient: Gradient = Gradient.new()
	var tint: Color = profile.get("shadow_color")
	gradient.set_color(0, tint)
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	gradient.add_point(0.3, Color(tint.r, tint.g, tint.b, tint.a * 0.85))
	gradient.add_point(0.7, Color(tint.r, tint.g, tint.b, tint.a * 0.3))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient
	_contact_shadow = Sprite2D.new()
	_contact_shadow.name = "RoomContactShadow"
	_contact_shadow.texture = texture
	_contact_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_contact_shadow.z_index = -1
	_contact_shadow.show_behind_parent = true
	_contact_shadow.position = profile.get("shadow_offset")
	if subject is Player:
		_contact_shadow.position += (subject as Player).floor_visual_offset()
	var radii: Vector2 = profile.get("shadow_radii")
	_contact_shadow.scale = radii.max(Vector2.ONE * 0.5) / 32.0
	subject.add_child(_contact_shadow)


func _remove_contact_shadow() -> void:
	if is_instance_valid(_contact_shadow):
		_contact_shadow.hide()
		_contact_shadow.get_parent().remove_child(_contact_shadow)
		_contact_shadow.queue_free()
	_contact_shadow = null
	if is_instance_valid(_original_shadow):
		_original_shadow.visible = _original_shadow_visible
	_original_shadow = null


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(update_frame):
		RenderingServer.frame_pre_draw.disconnect(update_frame)
	if profile != null and profile.changed.is_connected(apply_profile):
		profile.changed.disconnect(apply_profile)
	_remove_contact_shadow()
