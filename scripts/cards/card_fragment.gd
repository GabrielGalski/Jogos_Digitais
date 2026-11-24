extends Node2D
## Swept secondary projectile, shared by shrapnel and controlled monsters.
const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const ARROW_GLOW: Texture2D = preload("res://resources/visual/booster_opener_light.tres")
static var _arrow_tip: PackedVector2Array = PackedVector2Array([Vector2(4, 0), Vector2(-2, -2), Vector2(-1, 0), Vector2(-2, 2)])
static var _arrow_material: CanvasItemMaterial
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
	if attack != null:
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		if _arrow_material == null:
			_arrow_material = CanvasItemMaterial.new()
			_arrow_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			_arrow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = _arrow_material


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
		if not bool(hit.get("sound_block", false)) and enemy != null and enemy.has_method("is_alive") and bool(enemy.call("is_alive")):
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
	if attack != null:
		_draw_arrow()
	elif sheet != null:
		var size: Vector2 = Vector2(sheet.get_width() / float(frames), sheet.get_height())
		var frame: int = int(age * 12.0) % frames
		draw_set_transform(Vector2.ZERO, direction.angle())
		draw_texture_rect_region(sheet, Rect2(-size * 0.5, size), Rect2(Vector2(frame * size.x, 0), size))
	else:
		draw_rect(Rect2(-2, -2, 5, 4), Color("#08080c"))
		draw_rect(Rect2(-1, -1, 3, 2), Color("#9c82ac"))


func _draw_arrow() -> void:
	draw_set_transform(Vector2.ZERO, direction.angle())
	var fade: float = clampf(remaining / 0.12, 0.0, 1.0)
	var length: float = minf(age * speed, 26.0)
	for index: int in range(5):
		var fraction: float = float(index) / 5.0
		var from: Vector2 = Vector2(-length * fraction, 0.0)
		var to: Vector2 = Vector2(-length * (fraction + 0.2), 0.0)
		var strength: float = (1.0 - fraction) * fade
		draw_line(from, to, Color(1.0, 0.17, 0.025, strength * 0.32), lerpf(5.5, 1.0, fraction), true)
		draw_line(from, to, Color(1.0, 0.56, 0.05, strength * 0.95), lerpf(2.0, 0.5, fraction), true)
	draw_texture_rect(ARROW_GLOW, Rect2(-7.0, -8.0, 17.0, 16.0), false, Color(1.0, 0.32, 0.055, fade * 0.32))
	draw_colored_polygon(_arrow_tip, Color(1.0, 0.81, 0.28, fade))
	draw_rect(Rect2(0.0, -0.5, 2.0, 1.0), Color(1.0, 0.99, 0.85, fade))
