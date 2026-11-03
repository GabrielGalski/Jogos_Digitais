extends Node2D
## Beam/stream executor and procedural geometry; the runtime owns damage cadence.

const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
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


func advance(delta: float, origin: Vector2, aim: Vector2, requested: bool) -> void:
	if is_queued_for_deletion():
		return
	global_position = origin
	direction = aim.normalized() if not aim.is_zero_approx() else Vector2.RIGHT
	if requested:
		if not firing:
			firing_age = 0.0
		firing_age += delta
		idle_age = 0.0
	else:
		idle_age += delta
	firing = requested
	beam_target = null
	if model.family == ProceduralManifestationModel.Family.BEAM:
		visible = firing
		length = model.reach
		_update_beam_contact()
	else:
		visible = firing or idle_age < model.card.projectile_lifetime
		length = minf(model.reach, firing_age * model.card.projectile_speed)
		if not firing:
			length *= maxf(0.0, 1.0 - idle_age / model.card.projectile_lifetime)
		_limit_stream_by_wall()
	endpoint = direction * length
	halo.position = endpoint * 0.5
	halo.rotation = direction.angle()
	halo.scale = Vector2((length + 12.0) / 32.0, 0.4 if model.family == ProceduralManifestationModel.Family.BEAM else 1.2)
	tip.visible = model.family == ProceduralManifestationModel.Family.BEAM and firing
	tip.position = endpoint
	tip.rotation = direction.angle()
	tip.texture = factory.texture_for(model, int(firing_age * 16.0), Vector2.RIGHT)
	queue_redraw()


func _exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	if is_instance_valid(shooter):
		exclusions.append(shooter.get_rid())
	return exclusions


func _update_beam_contact() -> void:
	var hit: Dictionary = CONTACTS.sweep(get_tree(), get_world_2d().direct_space_state,
		global_position, global_position + direction * model.reach, 5, model.hit_radius, _exclusions())
	if hit.is_empty():
		return
	length = global_position.distance_to(hit.get("position") as Vector2)
	var body: Node2D = hit.get("collider") as Node2D
	if _valid_enemy(body):
		beam_target = body


func _limit_stream_by_wall() -> void:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position,
		global_position + direction * length, 1, _exclusions())
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		length = maxf(0.0, global_position.distance_to(hit.get("position") as Vector2) - 1.0)


func hit_targets() -> Array[Node2D]:
	var targets: Array[Node2D] = []
	if not firing:
		return targets
	if model.family == ProceduralManifestationModel.Family.BEAM:
		if _valid_enemy(beam_target):
			targets.append(beam_target)
		return targets
	var perpendicular: Vector2 = direction.orthogonal()
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
		var relative: Vector2 = point - global_position
		var along: float = relative.dot(direction)
		if along < -radius or along > length + radius:
			continue
		var half_width: float = lerpf(model.start_half_width, model.end_half_width, clampf(along / model.reach, 0.0, 1.0))
		if absf(relative.dot(perpendicular)) > half_width + radius:
			continue
		var cover_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, point, 1, _exclusions())
		if get_world_2d().direct_space_state.intersect_ray(cover_query).is_empty():
			targets.append(enemy)
	return targets


func _draw() -> void:
	if model == null or length < 1.0:
		return
	if model.family == ProceduralManifestationModel.Family.BEAM:
		draw_line(Vector2.ZERO, endpoint, Color(model.body_color, 0.18), 5.0, true)
		draw_line(Vector2.ZERO, endpoint, model.body_color, 2.1, true)
		draw_line(Vector2.ZERO, endpoint, model.core_color, 0.75 + sin(firing_age * 22.0) * 0.1, true)
		return
	var perpendicular: Vector2 = direction.orthogonal()
	var fade: float = 1.0 if firing else maxf(0.0, 1.0 - idle_age / model.card.projectile_lifetime)
	# Continuous flowing ribbons replace rows of disconnected, black-bordered tiles.
	for lane: int in [-1, 0, 1]:
		var previous: Vector2 = Vector2.ZERO
		for step: int in range(1, 33):
			var along: float = length * float(step) / 32.0
			var half_width: float = lerpf(model.start_half_width, model.end_half_width, along / model.reach)
			var wave: float = sin(along * 0.11 - firing_age * 12.0 + float(lane) * 1.7) * 1.8
			var spread: float = minf(1.0, along / 24.0)
			var point: Vector2 = direction * along + perpendicular * (float(lane) * half_width * 0.7 + wave) * spread
			var opacity: float = (1.0 - float(step) / 40.0) * fade
			draw_line(previous, point, Color(model.body_color, opacity * 0.7), 3.0, true)
			draw_line(previous, point, Color(model.core_color, opacity * 0.65), 0.7, true)
			previous = point
	var phase: float = fposmod(firing_age * model.card.projectile_speed, 16.0)
	for index: int in range(ceili(length / 16.0) + 1):
		var along: float = float(index) * 16.0 + phase
		if along > length:
			continue
		var half_width: float = lerpf(model.start_half_width, model.end_half_width, along / model.reach)
		for lane: int in [-1, 0, 1]:
			if lane != 0 and along < 18.0:
				continue
			var drift: float = sin(float(index) * 2.3 + float(lane) + firing_age * 12.0) * 1.5
			var center: Vector2 = direction * along + perpendicular * (float(lane) * half_width * 0.7 + drift)
			var texture: Texture2D = factory.texture_for(model, int(firing_age * 18.0) + index + lane, Vector2.RIGHT)
			var size: float = 32.0 * model.visual_scale
			draw_set_transform(center, direction.angle())
			draw_texture_rect(texture, Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false, Color(1, 1, 1, fade * 0.85))
	draw_set_transform(Vector2.ZERO)


func _valid_enemy(body: Node2D) -> bool:
	return is_instance_valid(body) and not body.is_queued_for_deletion() and body.has_method("is_alive") and bool(body.call("is_alive"))
