extends Node2D

const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const ART: Array[Texture2D] = [
	preload("res://assets/summons/bat/bat1.png"),
	preload("res://assets/summons/bat/bat2.png"),
	preload("res://assets/summons/bat/bat3.png"),
	preload("res://assets/summons/bat/bat4.png"),
	preload("res://assets/summons/bat/bat5.png"),
]
const HUNT_RADIUS: float = 120.0
const HEAL: float = 0.04

var player: Player
var service: Node
var angle: float
var search_in: float
var _sprite: Sprite2D
var _target: Node2D
var _returning: bool = false
var _age: float = 0.0


func _ready() -> void:
	z_index = 3
	_sprite = Sprite2D.new()
	_sprite.texture = ART[0]
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.dead:
		queue_free()
		return
	_age += delta
	if _age >= (9.0 if _returning else 6.0):
		queue_free()
		return
	var home: Vector2 = player.surface_world_position() - Vector2(0, 7)
	if _returning:
		_fly_to(home, 255.0, delta)
		if global_position.distance_squared_to(home) <= 16.0:
			player.heal_fraction(HEAL)
			queue_free()
		return
	if not is_instance_valid(_target) or not _valid(_target):
		_target = null
		search_in -= delta
		if search_in <= 0.0:
			search_in = 0.24
			_target = _find_target(home)
	if _target != null:
		var at: Vector2 = CONTACTS.damage_center(_target)
		if home.distance_squared_to(at) > HUNT_RADIUS * HUNT_RADIUS or not _path_clear(global_position, at):
			_target = null
			return
		_fly_to(at, 174.0, delta)
		if global_position.distance_squared_to(at) < 36.0:
			var combat: CombatEffects = service.call("effects") as CombatEffects
			_returning = combat.apply_hit(_target, 3.0, home.direction_to(at), 0.0)
			_target = null
		return
	angle += 4.0 * delta
	_fly_to(home + Vector2.from_angle(angle) * 19.0, 165.0, delta)


func _fly_to(at: Vector2, speed: float, delta: float) -> void:
	if absf(at.x - global_position.x) > 0.4:
		_sprite.flip_h = at.x < global_position.x
	global_position = global_position.move_toward(at, speed * delta)
	_sprite.texture = ART[floori(_age * 15.0) % ART.size()]


func _find_target(home: Vector2) -> Node2D:
	var best: float = HUNT_RADIUS * HUNT_RADIUS
	var selected: Node2D
	for enemy: Node2D in service.call("enemies"):
		var at: Vector2 = CONTACTS.damage_center(enemy)
		var distance: float = home.distance_squared_to(at)
		if distance < best and _path_clear(global_position, at) and _path_clear(home, at):
			best = distance
			selected = enemy
	return selected


func _valid(target: Node2D) -> bool:
	return is_instance_valid(target) and bool(service.call("valid_enemy", target))


func _path_clear(from: Vector2, to: Vector2) -> bool:
	if from.is_equal_approx(to):
		return true
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, 1, [player.get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()
