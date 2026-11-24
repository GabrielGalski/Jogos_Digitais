extends RefCounted
## Builds projectile-only cover on the sprite's projected pixel plane.

const CONTACTS: Script = preload("res://scripts/combat/projectile_enemy_contacts.gd")
const BORDER_TILES: Script = preload("res://scripts/dungeon/ldtk_borders.gd")


static func attach(sprite: Sprite2D) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "ProjectileCover"
	body.collision_layer = CONTACTS.SCENERY_LAYER
	body.collision_mask = 0
	body.add_to_group(CONTACTS.SCENERY_GROUP)
	var image: Image = sprite.texture.get_image()
	if image.is_compressed():
		image.decompress()
	var region: Rect2i = image.get_used_rect()
	for rect: Rect2i in BORDER_TILES.alpha_rectangles(image, region):
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = Vector2(rect.size)
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.shape = shape
		collider.position = Vector2(region.position + rect.position) + shape.size * 0.5
		body.add_child(collider)
	sprite.add_child(body)
