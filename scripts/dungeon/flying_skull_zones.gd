extends "res://scripts/dungeon/flying_eye_zones.gd"
var habitats: RefCounted = null


func configure(layers: Array, subject: Player, rules: Node2D, allowed: Dictionary,
		ground: Callable, height: Callable, encounters: Array) -> void:
	super.configure(layers, subject, rules, allowed, ground, height, encounters)
	for identifier: StringName in zones: (zones[identifier].config as Dictionary)["PackLimit"] = 1


func accepts_zone(rect: Rect2) -> bool:
	return habitats != null and bool(habitats.call("castle_zone", rect))


func accepts_spawn_point(point: Vector2) -> bool:
	return habitats != null and bool(habitats.call("is_castle", point))


func create_pack() -> Node2D:
	return (preload("res://scripts/enemies/flying_skull_pack.gd") as Script).new() as Node2D
