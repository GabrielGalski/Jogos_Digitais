extends Node2D
## Beam/stream executor and procedural geometry; the runtime owns damage cadence.

const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const STREAM_REAR_REACH: float = 16.0
const STREAM_VISUAL_TAIL: float = 0.08
static var _flame_texture: ImageTexture

var model: ProceduralManifestationModel
var factory: ProceduralWeaponSpriteFactory
var shooter: CollisionObject2D
var direction: Vector2 = Vector2.RIGHT
var firing: bool = true
var firing_age: float = 0.0
var idle_age: float = 0.0
var length: float = 0.0
var endpoint: Vector2 = Vector2.ZERO
var beam_target: Node2D = null
var tip: Sprite2D = null
var halo: Sprite2D = null
var mode: StringName = &""
var element_color: Color = Color.WHITE
var _base_material: Material
var _element_phase: int = -1
var _jet: CPUParticles2D
var _sparks: CPUParticles2D
var _ricochet: bool
var _beam_reflected: bool
var _beam_reflected_from_enemy: bool
var _reflected_beam_target: Node2D
var _enemy_bounce_claimed: bool
var _enemy_bounce_target: Node2D
var _stream_contact_target: Node2D
var _beam_out: Vector2
var _bend: Vector2
var _reflected_jet: CPUParticles2D
var _reflected_sparks: CPUParticles2D
var _reflected_origin: Vector2
var _reflected_direction: Vector2
var _reflected_length: float = 0.0
var _stream_hit_directions: Dictionary[int, Vector2] = {}


func configure(definition: ProceduralManifestationModel, sprites: ProceduralWeaponSpriteFactory, caster: CollisionObject2D) -> void:
	model = definition
	factory = sprites
	shooter = caster
	mode = model.code()
	add_to_group(&"player_projectiles")
	add_to_group(&"manifestation_projectiles")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var opaque: CanvasItemMaterial = CanvasItemMaterial.new()
	opaque.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = opaque
	_base_material = opaque
	if model.family == ProceduralManifestationModel.Family.STREAM:
		_configure_flame()
		return
	var additive: CanvasItemMaterial = opaque.duplicate() as CanvasItemMaterial
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo = Sprite2D.new()
	halo.name = "ChannelHalo"
	halo.texture = factory.glow_texture()
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	halo.material = additive
	halo.modulate = Color(model.body_color, 0.13)
	add_child(halo)
	tip = Sprite2D.new()
	tip.name = "Tip32"
	tip.material = opaque
	tip.scale = Vector2.ONE * model.visual_scale * float(factory.SIZE) / float(factory.RENDER_SIZE)
	add_child(tip)


func advance(delta: float, origin: Vector2, aim: Vector2, requested: bool, ricochet: bool = false) -> void:
	if is_queued_for_deletion():
		return
	if requested:
		global_position = origin
		direction = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT
		if not firing:
			firing_age = 0.0
		firing_age += delta
		idle_age = 0.0
	else:
		idle_age += delta
	firing = requested
	_ricochet = ricochet
	beam_target = null
	_reflected_beam_target = null
	_stream_contact_target = null
	if not requested or not _ricochet:
		_enemy_bounce_claimed = false
		_enemy_bounce_target = null
	if model.family == ProceduralManifestationModel.Family.STREAM:
		_update_flame()
		return
	visible = firing
	if not firing:
		return
	length = model.reach
	_update_beam_contact()
	halo.position = direction * length * 0.5
	halo.rotation = direction.angle()
	halo.scale = Vector2((length + 12.0) / 32.0, 0.4)
	tip.position = endpoint
	tip.rotation = _beam_out.angle()
	tip.texture = factory.texture_for(model, int(firing_age * 16.0), Vector2.RIGHT)
	queue_redraw()


func set_element(phase: int) -> void:
	if phase == _element_phase:
		return
	_element_phase = phase
	var colors: Array[Color] = [Color("#fa412d"), Color("#67e649"), Color("#ffdc45")]
	element_color = Color.WHITE if phase < 0 else colors[phase]
	if model.family == ProceduralManifestationModel.Family.STREAM:
		var ramp: Gradient = _flame_color_ramp()
		_jet.color_ramp = ramp
		_sparks.color_ramp = ramp
		if _reflected_jet != null:
			_reflected_jet.color_ramp = ramp
			_reflected_sparks.color_ramp = ramp
		return
	if phase < 0:
		material = _base_material
		tip.material = _base_material
		halo.modulate = Color(model.body_color, 0.13)
		return
	halo.modulate = Color(element_color, 0.3)
	var shader: ShaderMaterial = ShaderMaterial.new()
	shader.shader = preload("res://shaders/chimera_projectile.gdshader")
	shader.set_shader_parameter(&"element_color", element_color)
	tip.material = shader
	material = shader


func _exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	if is_instance_valid(shooter):
		exclusions.append(shooter.get_rid())
	return exclusions


func _update_beam_contact() -> void:
	_beam_reflected = false
	_beam_reflected_from_enemy = false
	_beam_out = direction
	endpoint = direction * model.reach
	var hit: Dictionary = CONTACTS.sweep(get_tree(), get_world_2d().direct_space_state,
		global_position, global_position + direction * model.reach, 5, model.hit_radius, _exclusions())
	if hit.is_empty():
		return
	length = global_position.distance_to(hit.get("position") as Vector2)
	endpoint = direction * length
	if bool(hit.get("sound_block", false)):
		return
	var body: Node2D = hit.get("collider") as Node2D
	if _valid_enemy(body):
		beam_target = body
	if not _ricochet:
		return
	var remaining_reach: float = model.reach - length
	if remaining_reach <= 1.0:
		return
	var reflected: Vector2 = _channel_reflection(hit, beam_target)
	if reflected.is_zero_approx():
		return
	_beam_reflected = true
	_beam_reflected_from_enemy = beam_target != null
	_beam_out = reflected
	_bend = endpoint
	var start: Vector2 = global_position + _bend + (hit.normal as Vector2) * 0.6
	var end: Vector2 = start + reflected * remaining_reach
	var passed: Dictionary[int, bool] = {}
	if is_instance_valid(beam_target):
		passed[beam_target.get_instance_id()] = true
	hit = CONTACTS.sweep(get_tree(), get_world_2d().direct_space_state,
		start, end, 5, model.hit_radius, _exclusions(), passed)
	endpoint = (hit.get("position", end) as Vector2) - global_position
	if not bool(hit.get("sound_block", false)):
		body = hit.get("collider") as Node2D
		if _valid_enemy(body):
			if beam_target == null:
				beam_target = body
			else:
				_reflected_beam_target = body


func _channel_reflection(contact: Dictionary, enemy: Node2D) -> Vector2:
	if not _valid_enemy(enemy):
		return CONTACTS.wall_reflection(contact, direction)
	# Claim one enemy for the entire held attack, even after it dies.
	if _enemy_bounce_claimed and _enemy_bounce_target != enemy:
		return Vector2.ZERO
	var reflected: Vector2 = CONTACTS.contact_reflection(contact, direction)
	if not reflected.is_zero_approx():
		_enemy_bounce_claimed = true
		_enemy_bounce_target = enemy
	return reflected


func hit_direction(target: Node2D = null) -> Vector2:
	if model.family == ProceduralManifestationModel.Family.BEAM:
		if _beam_reflected_from_enemy and target != null and target == beam_target:
			return direction
		return _beam_out
	if is_instance_valid(target):
		return _stream_hit_directions.get(target.get_instance_id(), direction)
	return direction


func _update_flame() -> void:
	_reflected_length = 0.0
	if firing:
		global_rotation = direction.angle()
		var speed: float = model.card.projectile_speed
		var travel: float = minf(model.reach, firing_age * speed)
		var wall: Dictionary = _trace_stream(global_position, direction, model.reach)
		var clear_reach: float = model.reach
		if _ricochet and (not _enemy_bounce_claimed or _valid_enemy(_enemy_bounce_target)):
			var contact: Dictionary = CONTACTS.sweep(get_tree(), get_world_2d().direct_space_state,
				global_position, global_position + direction * travel, 5, 0.0, _exclusions())
			var enemy: Node2D = contact.get("collider") as Node2D
			if not bool(contact.get("sound_block", false)) and _valid_enemy(enemy):
				var reflected: Vector2 = _channel_reflection(contact, enemy)
				if not reflected.is_zero_approx():
					_stream_contact_target = enemy
					clear_reach = global_position.distance_to(contact.position as Vector2)
					_update_reflected_flame(contact, reflected, clear_reach, travel, speed)
		if _stream_contact_target == null and not wall.is_empty():
			var wall_distance: float = global_position.distance_to(wall.position as Vector2)
			clear_reach = maxf(0.0, wall_distance - 1.0)
			if _ricochet and travel > wall_distance:
				_update_reflected_flame(wall, CONTACTS.wall_reflection(wall, direction), wall_distance, travel, speed)
		length = minf(clear_reach, travel)
		endpoint = direction * length
		var lifetime: float = model.card.projectile_lifetime
		if clear_reach < model.reach:
			lifetime = clampf(clear_reach / speed, 0.01, lifetime)
		_jet.lifetime = lifetime
		_sparks.lifetime = lifetime
	var emit_flame: bool = firing and length > 0.0
	_jet.emitting = emit_flame
	_sparks.emitting = emit_flame
	if _reflected_jet != null:
		_reflected_jet.emitting = _reflected_length > 0.0
		_reflected_sparks.emitting = _reflected_jet.emitting
	visible = firing or idle_age < model.card.projectile_lifetime + STREAM_VISUAL_TAIL


func _trace_stream(start: Vector2, aim: Vector2, reach: float) -> Dictionary:
	return CONTACTS.sweep(get_tree(), get_world_2d().direct_space_state,
		start, start + aim * reach, 1, 0.0, _exclusions())


func _update_reflected_flame(contact: Dictionary, reflected: Vector2, wall_distance: float, travel: float, speed: float) -> void:
	_reflected_direction = reflected
	if _reflected_direction.is_zero_approx():
		return
	_reflected_origin = (contact.position as Vector2) + (contact.normal as Vector2) * 0.6
	var reach: float = model.reach - wall_distance
	var obstacle: Dictionary = _trace_stream(_reflected_origin, _reflected_direction, reach)
	if not obstacle.is_empty():
		reach = maxf(0.0, _reflected_origin.distance_to(obstacle.position as Vector2) - 1.0)
	_reflected_length = minf(reach, travel - wall_distance)
	if _reflected_length <= 0.0:
		return
	if _reflected_jet == null:
		_reflected_jet = _jet.duplicate() as CPUParticles2D
		_reflected_jet.name = "ReflectedJet"
		_reflected_jet.amount = 72
		add_child(_reflected_jet)
		_reflected_sparks = _sparks.duplicate() as CPUParticles2D
		_reflected_sparks.name = "ReflectedSparks"
		_reflected_sparks.amount = 16
		add_child(_reflected_sparks)
	for emitter: CPUParticles2D in [_reflected_jet, _reflected_sparks]:
		emitter.global_position = _reflected_origin
		emitter.global_rotation = _reflected_direction.angle()
		emitter.lifetime = clampf(reach / speed, 0.01, model.card.projectile_lifetime)


func hit_targets() -> Array[Node2D]:
	var targets: Array[Node2D] = []
	if not firing:
		return targets
	if model.family == ProceduralManifestationModel.Family.BEAM:
		if is_instance_valid(beam_target) and _valid_enemy(beam_target):
			targets.append(beam_target)
		if _valid_enemy(_reflected_beam_target):
			targets.append(_reflected_beam_target)
		return targets
	_stream_hit_directions.clear()
	var exclusions: Array[RID] = _exclusions()
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for candidate: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = candidate as Node2D
		if not _valid_enemy(enemy):
			continue
		var point: Vector2 = enemy.global_position
		var radius: float = 3.0
		if enemy.has_method("get_projectile_hurt_capsule"):
			var capsule: Dictionary = enemy.call("get_projectile_hurt_capsule") as Dictionary
			point = enemy.to_global(capsule.get("center", Vector2.ZERO) as Vector2)
			radius = float(capsule.get("radius", 3.0))
		if enemy == _stream_contact_target or _stream_reaches(global_position, direction, length, STREAM_REAR_REACH, point, radius, space, exclusions):
			targets.append(enemy)
		elif _reflected_length > 0.0 and _stream_reaches(_reflected_origin, _reflected_direction,
				_reflected_length, 0.0, point, radius, space, exclusions):
			targets.append(enemy)
			_stream_hit_directions[enemy.get_instance_id()] = _reflected_direction
	return targets


func _stream_reaches(origin: Vector2, aim: Vector2, reach: float, rear_reach: float,
		point: Vector2, radius: float, space: PhysicsDirectSpaceState2D, exclusions: Array[RID]) -> bool:
	var relative: Vector2 = point - origin
	var along: float = relative.dot(aim)
	if along < -rear_reach - radius or along > reach + radius:
		return false
	var half_width: float = lerpf(model.start_half_width, model.end_half_width, clampf(along / model.reach, 0.0, 1.0))
	if absf(relative.dot(aim.orthogonal())) > half_width + radius:
		return false
	if not CONTACTS.sound_field_hit(get_tree(), origin, point, 0.0).is_empty():
		return false
	return CONTACTS.terrain_ray(get_tree(), space, origin, point, 1, exclusions).is_empty()


func _draw() -> void:
	if model == null or model.family != ProceduralManifestationModel.Family.BEAM or length < 1.0:
		return
	_draw_beam_leg(Vector2.ZERO, _bend if _beam_reflected else endpoint)
	if _beam_reflected:
		_draw_beam_leg(_bend, endpoint)


func _draw_beam_leg(start: Vector2, end: Vector2) -> void:
	draw_line(start, end, Color(model.body_color, 0.18), 5.0, true)
	draw_line(start, end, model.body_color if element_color == Color.WHITE else element_color, 2.1, true)
	draw_line(start, end, model.core_color, 0.75 + sin(firing_age * 22.0) * 0.1, true)


func _configure_flame() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _flame_texture == null:
		var pixels: Image = Image.create(9, 9, false, Image.FORMAT_RGBA8)
		pixels.fill(Color.TRANSPARENT)
		for y: int in range(1, 8):
			for x: int in range(1, 8):
				if absi(x - 4) + absi(y - 4) <= 5:
					pixels.set_pixel(x, y, Color.WHITE)
		_flame_texture = ImageTexture.create_from_image(pixels)
	var growth: Curve = Curve.new()
	growth.add_point(Vector2(0.0, 0.35))
	growth.add_point(Vector2(0.18, 0.75))
	growth.add_point(Vector2(0.65, 1.0))
	growth.add_point(Vector2(1.0, 0.30))
	var ramp: Gradient = _flame_color_ramp()
	_jet = _make_emitter(&"Jet", 144, 6.5, Vector2(0.65, 1.20), growth, ramp)
	_sparks = _make_emitter(&"EdgeSparks", 32, 8.0, Vector2(0.20, 0.40), growth, ramp)
	_sparks.angular_velocity_min = -110.0
	_sparks.angular_velocity_max = 110.0


func _make_emitter(emitter_name: StringName, amount: int, spread: float, scale_range: Vector2,
		growth: Curve, ramp: Gradient) -> CPUParticles2D:
	var emitter: CPUParticles2D = CPUParticles2D.new()
	emitter.name = emitter_name
	emitter.emitting = false
	emitter.amount = amount
	emitter.lifetime = model.card.projectile_lifetime
	emitter.local_coords = false
	emitter.direction = Vector2.RIGHT
	emitter.spread = spread
	emitter.gravity = Vector2.ZERO
	emitter.initial_velocity_min = 315.0
	emitter.initial_velocity_max = 335.0
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emitter.emission_rect_extents = Vector2(0.0, 1.5)
	emitter.scale_amount_min = scale_range.x
	emitter.scale_amount_max = scale_range.y
	emitter.scale_amount_curve = growth
	emitter.color_ramp = ramp
	emitter.texture = _flame_texture
	emitter.material = _base_material
	emitter.use_fixed_seed = true
	emitter.seed = 2667 + amount
	emitter.fixed_fps = 60
	add_child(emitter)
	return emitter


func _flame_color_ramp() -> Gradient:
	var colors: PackedColorArray = PackedColorArray([
		model.core_color, model.body_color, Color("#fa6a0a"), model.shadow_color, Color(model.shadow_color, 0.0)
	])
	if _element_phase >= 0:
		colors = PackedColorArray([
			element_color.lightened(0.55), element_color.lightened(0.22), element_color,
			element_color.darkened(0.32), Color(element_color.darkened(0.32), 0.0)
		])
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.24, 0.58, 0.82, 1.0])
	ramp.colors = colors
	return ramp


func _valid_enemy(body: Node2D) -> bool:
	return is_instance_valid(body) and not body.is_queued_for_deletion() and body.has_method("is_alive") and bool(body.call("is_alive"))
