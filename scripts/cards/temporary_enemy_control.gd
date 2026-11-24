extends Node2D
## Owns and restores one enemy's temporary movement/attack override.
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const SLAAD: Array[Texture2D] = [
	preload("res://assets/cards/infusao/ovo_de_slaad I04/slaad/slad1.png"),
	preload("res://assets/cards/infusao/ovo_de_slaad I04/slaad/slad2.png"),
	preload("res://assets/cards/infusao/ovo_de_slaad I04/slaad/slad3.png"),
]
var service: Node
var decoy: Node2D
var parasite: bool = true
var duration: float = 12.0
var enemy: CharacterBody2D
var previous_processing: bool
var elapsed: float = 0.0
var cooldown: float = 0.0
var visual: Sprite2D


func _ready() -> void:
	enemy = get_parent() as CharacterBody2D
	previous_processing = enemy.is_physics_processing()
	if enemy.has_method("cancel_attack"):
		enemy.call("cancel_attack")
	enemy.set_physics_process(false)
	enemy.set_meta(&"card_control", self)
	if parasite:
		enemy.add_to_group(&"controlled_monsters")
		visual = Sprite2D.new()
		visual.texture = SLAAD[0]
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.z_index = 5
		add_child(visual)


func _physics_process(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(service) or not bool(enemy.call("is_alive")):
		queue_free()
		return
	if elapsed >= duration:
		if parasite:
			service.call("expire_slaad", enemy)
		queue_free()
		return
	var target: Node2D = service.call("nearest_enemy", enemy.global_position, 320.0, enemy) as Node2D if parasite else decoy
	if visual != null:
		visual.texture = SLAAD[int(elapsed * 8.0) % SLAAD.size()]
		visual.position = enemy.to_local(CONTACTS.damage_center(enemy)) + Vector2(5, -4)
	if not is_instance_valid(target):
		return
	var reach: float = 110.0 if parasite else 18.0
	var distance: float = enemy.global_position.distance_to(target.global_position)
	if distance > reach:
		var direction: Vector2 = service.call("companion_direction", enemy.global_position, target.global_position) as Vector2
		enemy.velocity = direction * 65.0
		if service.call("has_floor", enemy.global_position + enemy.velocity * delta):
			enemy.move_and_slide()
	else:
		enemy.velocity = Vector2.ZERO
	if enemy.has_method("sync_floor_height"):
		enemy.call("sync_floor_height")
	cooldown -= delta
	if parasite and distance <= reach and cooldown <= 0.0:
		cooldown = 0.75
		service.call("controlled_attack", enemy, target)


func _exit_tree() -> void:
	if not is_instance_valid(enemy):
		return
	if enemy.get_meta(&"card_control", null) == self:
		enemy.remove_meta(&"card_control")
		if enemy.is_inside_tree() and bool(enemy.call("is_alive")):
			enemy.set_physics_process(previous_processing)
	if parasite and enemy.is_in_group(&"controlled_monsters"):
		enemy.remove_from_group(&"controlled_monsters")
