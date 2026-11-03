extends RefCounted
## Sweeps the bullet's width through damage-only capsules; movement shapes stay intact.


static func sweep(tree: SceneTree, space: PhysicsDirectSpaceState2D, origin: Vector2,
		endpoint: Vector2, mask: int, projectile_radius: float, exclusions: Array[RID] = []) -> Dictionary:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, endpoint, mask, exclusions)
	var nearest: Dictionary = space.intersect_ray(query)
	var travel: float = origin.distance_to(endpoint)
	var fraction: float = origin.distance_to(nearest.get("position", endpoint) as Vector2) / maxf(travel, 0.001) if not nearest.is_empty() else 1.0001
	if (mask & 4) == 0:
		return nearest
	for candidate: Node in tree.get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = candidate as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or not enemy.has_method("get_projectile_hurt_capsule"):
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
		var cover_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, enemy.to_global(center), mask & 1, exclusions)
		if (mask & 1) != 0 and not space.intersect_ray(cover_query).is_empty():
			continue
		fraction = float(hit.get("fraction"))
		nearest = {
			"collider": enemy, "position": origin.lerp(endpoint, fraction),
			"normal": enemy.global_transform.basis_xform(hit.get("normal") as Vector2).normalized(),
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
