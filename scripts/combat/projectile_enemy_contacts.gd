extends RefCounted
## Sweeps the bullet's width through damage-only capsules; movement shapes stay intact.

const WALL_RICOCHET_SPEED: float = 1.75
const SCENERY_LAYER: int = 1 << 6
const SCENERY_GROUP: StringName = &"projectile_scenery"
const MOVEMENT_ONLY: StringName = &"projectile_movement_only"


static func wall_reflection(contact: Dictionary, incoming: Vector2) -> Vector2:
	if not contact.has("rid") or bool(contact.get("sound_block", false)):
		return Vector2.ZERO
	if (PhysicsServer2D.body_get_collision_layer(contact.rid) & (1 | SCENERY_LAYER)) == 0:
		return Vector2.ZERO
	return contact_reflection(contact, incoming)


static func contact_reflection(contact: Dictionary, incoming: Vector2) -> Vector2:
	var normal: Vector2 = contact.get("normal", Vector2.ZERO) as Vector2
	if normal.is_zero_approx() or incoming.dot(normal) >= -0.001:
		return Vector2.ZERO
	return incoming.bounce(normal).normalized()


static func terrain_ray(tree: SceneTree, space: PhysicsDirectSpaceState2D, origin: Vector2,
		endpoint: Vector2, mask: int, exclusions: Array[RID] = [], visual_offset: Vector2 = Vector2.ZERO) -> Dictionary:
	var excluded: Array[RID] = exclusions.duplicate()
	if (mask & 1) != 0:
		for body: StaticBody2D in tree.get_nodes_in_group(MOVEMENT_ONLY):
			excluded.append(body.get_rid())
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, endpoint, mask, excluded)
	var nearest: Dictionary = space.intersect_ray(query)
	if (mask & 1) == 0 or not tree.has_group(SCENERY_GROUP):
		return nearest
	var visual_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		origin + visual_offset, endpoint + visual_offset, SCENERY_LAYER, exclusions)
	visual_query.hit_from_inside = true
	var cover: Dictionary = space.intersect_ray(visual_query)
	if cover.is_empty():
		return nearest
	var point: Vector2 = (cover.position as Vector2) - visual_offset
	if nearest.is_empty() or origin.distance_squared_to(point) < origin.distance_squared_to(nearest.position as Vector2):
		cover.position = point
		return cover
	return nearest


static func damage_center(enemy: Node2D) -> Vector2:
	if enemy.has_method("get_projectile_hurt_capsule"):
		var capsule: Dictionary = enemy.call("get_projectile_hurt_capsule") as Dictionary
		return enemy.to_global(capsule.get("center", Vector2.ZERO) as Vector2)
	return enemy.global_position


static func sweep(tree: SceneTree, space: PhysicsDirectSpaceState2D, origin: Vector2,
		endpoint: Vector2, mask: int, projectile_radius: float, exclusions: Array[RID] = [],
		passed_enemies: Dictionary[int, bool] = {}) -> Dictionary:
	var candidates: Array[Node] = tree.get_nodes_in_group(&"enemy_bodies")
	var physical_exclusions: Array[RID] = exclusions.duplicate()
	if (mask & 4) != 0:
		# A movement body at ground level must not replace a projected damage capsule.
		for candidate: Node in candidates:
			if candidate is CollisionObject2D and (candidate.has_method("get_projectile_hurt_capsule")
					or candidate.is_in_group(&"controlled_monsters") or passed_enemies.has(candidate.get_instance_id())):
				physical_exclusions.append((candidate as CollisionObject2D).get_rid())
	var nearest: Dictionary = terrain_ray(tree, space, origin, endpoint, mask, physical_exclusions)
	var travel: float = origin.distance_to(endpoint)
	var fraction: float = origin.distance_to(nearest.get("position", endpoint) as Vector2) / maxf(travel, 0.001) if not nearest.is_empty() else 1.0001
	var barrier: Dictionary = sound_field_hit(tree, origin, endpoint, projectile_radius)
	if not barrier.is_empty() and float(barrier.fraction) <= fraction:
		fraction = float(barrier.fraction)
		nearest = barrier
	if (mask & 4) == 0:
		return nearest
	for candidate: Node in candidates:
		var enemy: Node2D = candidate as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or not enemy.has_method("get_projectile_hurt_capsule"):
			continue
		if passed_enemies.has(enemy.get_instance_id()) or enemy.is_in_group(&"controlled_monsters"):
			continue
		if not enemy.has_method("is_alive") or not bool(enemy.call("is_alive")):
			continue
		var body: CollisionObject2D = enemy as CollisionObject2D
		if body != null and (exclusions.has(body.get_rid()) or (body.collision_layer & mask) == 0):
			continue
		var capsule: Dictionary = enemy.call("get_projectile_hurt_capsule") as Dictionary
		var center: Vector2 = capsule.get("center", Vector2.ZERO) as Vector2
		var radius: float = maxf(float(capsule.get("radius", 0.0)), 0.0)
		var stem: float = maxf(float(capsule.get("height", radius * 2.0)) * 0.5 - radius, 0.0)
		var actor_scale: float = maxf(minf(absf(enemy.global_scale.x), absf(enemy.global_scale.y)), 0.001)
		var hit: Dictionary = _capsule_hit(enemy.to_local(origin), enemy.to_local(endpoint), center,
			radius + projectile_radius / actor_scale, stem)
		if hit.is_empty() or float(hit.get("fraction")) >= fraction:
			continue
		# A generous capsule must not protrude through a wall and take damage through it.
		if (mask & 1) != 0 and not terrain_ray(tree, space, origin, enemy.to_global(center), 1, exclusions).is_empty():
			continue
		fraction = float(hit.get("fraction"))
		nearest = {
			"collider": enemy, "position": origin.lerp(endpoint, fraction),
			"normal": enemy.global_transform.basis_xform(hit.get("normal") as Vector2).normalized(),
		}
	return nearest


static func sound_field_hit(tree: SceneTree, origin: Vector2, endpoint: Vector2, projectile_radius: float) -> Dictionary:
	var nearest: Dictionary = {}
	var fraction: float = 1.0001
	for field: Node2D in tree.get_nodes_in_group(&"sound_fields"):
		var radius: float = float(field.call("sound_field_radius")) + projectile_radius
		var hit: Dictionary = _capsule_hit(origin, endpoint, field.global_position, radius, 0.0)
		if hit.is_empty() or float(hit.fraction) >= fraction:
			continue
		fraction = float(hit.fraction)
		nearest = {
			"sound_block": true, "fraction": fraction, "position": origin.lerp(endpoint, fraction),
			"normal": hit.normal, "collider": field,
		}
	return nearest


static func _capsule_hit(origin: Vector2, endpoint: Vector2, center: Vector2,
		radius: float, stem: float) -> Dictionary:
	var motion: Vector2 = endpoint - origin
	var closest: Vector2 = Vector2(center.x, clampf(origin.y, center.y - stem, center.y + stem))
	var offset: Vector2 = origin - closest
	if offset.length_squared() <= radius * radius:
		return {"fraction": 0.0, "normal": offset.normalized() if not offset.is_zero_approx() else -motion.normalized()}
	var best: Dictionary = {}
	var fraction: float = 1.0001
	var square_length: float = motion.length_squared()
	if square_length < 0.000001:
		return best
	for cap: Vector2 in [center + Vector2(0, -stem), center + Vector2(0, stem)]:
		var relative: Vector2 = origin - cap
		var along: float = relative.dot(motion)
		var discriminant: float = along * along - square_length * (relative.length_squared() - radius * radius)
		if discriminant < 0.0:
			continue
		var entry: float = (-along - sqrt(discriminant)) / square_length
		if entry >= 0.0 and entry <= 1.0 and entry < fraction:
			fraction = entry
			best = {"fraction": entry, "normal": (origin + motion * entry - cap).normalized()}
	if absf(motion.x) > 0.000001:
		for side: float in [-1.0, 1.0]:
			var entry: float = (center.x + side * radius - origin.x) / motion.x
			var contact_y: float = origin.y + motion.y * entry
			if entry >= 0.0 and entry <= 1.0 and entry < fraction and absf(contact_y - center.y) <= stem:
				fraction = entry
				best = {"fraction": entry, "normal": Vector2(side, 0.0)}
	return best


static func capsule_hit(origin: Vector2, endpoint: Vector2, center: Vector2, radius: float, stem: float) -> Dictionary:
	return _capsule_hit(origin, endpoint, center, radius, maxf(stem, 0.0))
