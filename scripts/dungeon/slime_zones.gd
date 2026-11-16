extends "res://scripts/dungeon/flying_eye_zones.gd"
var habitats: RefCounted = null
var remains_system: Node2D = null


func configure(layers: Array, subject: Player, rules: Node2D, allowed: Dictionary,
		ground: Callable, height: Callable, encounters: Array) -> void:
	profile.minimum_pack_size = 3
	profile.maximum_pack_size = 5
	profile.body_radius = 7.0
	profile.anchor_leash = 224.0
	profile.spawn_interval = 0.40
	profile.minimum_anchor_distance = 192.0
	super.configure(layers, subject, rules, allowed, ground, height, encounters)
	for identifier: StringName in zones:
		var config: Dictionary = zones[identifier].config as Dictionary
		config["PackLimit"] = 2
		config["MinimumPackDistancePx"] = profile.minimum_anchor_distance


func accepts_zone(rect: Rect2) -> bool:
	return habitats != null and bool(habitats.call("slime_zone", rect))


func accepts_spawn_point(point: Vector2) -> bool:
	return habitats != null and bool(habitats.call("slime_support", point))


func spawn_weight(point: Vector2) -> float:
	return float(habitats.call("slime_weight", point)) if habitats != null else 0.0


func create_pack() -> Node2D:
	var pack: Node2D = (preload("res://scripts/enemies/slime_pack.gd") as Script).new() as Node2D
	pack.set("remains_system", remains_system)
	return pack


func _safe_spawn(_anchor: Vector2, members: Array[Vector2], view: Rect2) -> bool:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 8.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 5
	for point: Vector2 in members:
		if not accepts_spawn_point(point): return false
		var height: float = float(_height_query.call(point))
		if view.grow(profile.spawn_padding + 16.0).has_point(point - Vector2(0, height + 8)): return false
		query.transform = Transform2D(0.0, point)
		if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	return true
