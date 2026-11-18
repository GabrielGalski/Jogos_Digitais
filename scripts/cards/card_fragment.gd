extends Node2D
## Swept secondary projectile, shared by shrapnel and controlled monsters.
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
var attack: CardAttack
var effects: CombatEffects
var damage: float = 1.0
var direction: Vector2 = Vector2.RIGHT
var speed: float = 150.0
var remaining: float = 0.65
var excluded: Array[RID] = []
var sheet: Texture2D
var frames: int = 1
var age: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 3
	add_to_group(&"card_fragments")


func _physics_process(delta: float) -> void:
	remaining -= delta
	age += delta
	if remaining <= 0.0:
		queue_free()
		return
	var endpoint: Vector2 = global_position + direction * speed * delta
	var hit: Dictionary = CONTACTS.sweep(get_tree(), get_world_2d().direct_space_state, global_position, endpoint, 5, 2.0, excluded)
	if not hit.is_empty():
		var enemy: Node2D = hit.get("collider") as Node2D
		if enemy != null and enemy.has_method("is_alive") and bool(enemy.call("is_alive")):
			if attack != null:
				attack.apply_secondary_hit(enemy, damage, direction, effects)
			elif is_instance_valid(effects):
				effects.apply_hit(enemy, damage, direction, 20.0)
		queue_free()
		set_physics_process(false)
	else:
		global_position = endpoint
	queue_redraw()


func _draw() -> void:
	if sheet != null:
		var size: Vector2 = Vector2(sheet.get_width() / float(frames), sheet.get_height())
		var frame: int = int(age * 12.0) % frames
		draw_set_transform(Vector2.ZERO, direction.angle())
		draw_texture_rect_region(sheet, Rect2(-size * 0.5, size), Rect2(Vector2(frame * size.x, 0), size))
	else:
		draw_rect(Rect2(-2, -2, 5, 4), Color("#08080c"))
		draw_rect(Rect2(-1, -1, 3, 2), Color("#9c82ac"))
