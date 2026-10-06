extends SceneTree

const AMBIENT: Script = preload("res://scripts/dungeon/ldtk_ambient_areas.gd")
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")


func _initialize() -> void:
	_run.call_deferred()


func _entity(id: String, fields: Dictionary, at: Vector2 = Vector2(-32, 24)) -> Dictionary:
	var instances: Array[Dictionary] = []
	for identifier: String in fields:
		instances.append({"__identifier": identifier, "__value": fields[identifier]})
	return {"__identifier": "AmbientArea", "iid": id, "px": [at.x, at.y],
		"width": 24, "height": 32, "__pivot": [0, 0], "fieldInstances": instances}


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://monster_booster.ldtk")) as Dictionary
	var definition: Dictionary = {}
	for entity: Dictionary in (data.defs as Dictionary).entities:
		if str(entity.identifier) == "AmbientArea":
			definition = entity
	assert(not definition.is_empty() and bool(definition.allowOutOfBounds))
	assert(bool(definition.resizableX) and bool(definition.resizableY))
	var manager: Node2D = AMBIENT.new() as Node2D
	manager.set("random_seed", 1234)
	manager.set("only_when_on_screen", false)
	manager.set("max_simultaneous", 1)
	root.add_child(manager)
	var layers: Array = [{"__type": "Entities", "visible": true,
		"__pxTotalOffsetX": 8, "__pxTotalOffsetY": 16, "entityInstances": [
			_entity("eye", {"AnimationId": "eye", "Chance": 1.0, "RepeatCount": 2, "FlipX": true, "FPS": 20.0}),
			_entity("disabled", {"AnimationId": "eye", "Enabled": false}),
			_entity("never", {"AnimationId": "eye", "Chance": 0.0}),
			_entity("mouth", {"AnimationId": "mouth"}),
		]}]
	manager.call("configure", layers, TEXTURES.new())
	manager.set_process(false)
	var slots: Array = manager.get("slots") as Array
	assert(slots.size() == 4 and int(manager.z_index) < -20)
	assert(manager.find_children("*", "CollisionObject2D", true, false).is_empty())
	assert(manager.find_children("*", "CollisionShape2D", true, false).is_empty())
	for slot: Dictionary in slots:
		assert(not bool(slot.ready) and not (slot.sprite as AnimatedSprite2D).visible)
		assert(float(slot.remaining) >= 6.0 and float(slot.remaining) <= 18.0)
	manager.call("_process", 100.0)
	assert(int(manager.get("_active_count")) == 0, "Unbound areas created placeholder art")
	var frames: SpriteFrames = SpriteFrames.new()
	frames.set_animation_loop(&"default", false)
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	frames.add_frame(&"default", texture)
	frames.add_frame(&"default", texture)
	assert(int(manager.call("bind_animation", "eye", frames)) == 3)
	(slots[0] as Dictionary).remaining = 0.0
	(slots[2] as Dictionary).remaining = 0.0
	manager.call("_process", 0.1)
	var first: Dictionary = slots[0]
	var sprite: AnimatedSprite2D = first.sprite as AnimatedSprite2D
	assert(bool(first.active) and sprite.visible and sprite.flip_h)
	assert((first.rect as Rect2).has_point(sprite.position))
	assert((first.rect as Rect2).position.is_equal_approx(Vector2(-24, 40)))
	assert(not bool((slots[1] as Dictionary).active) and not bool((slots[2] as Dictionary).active))
	assert(not bool((slots[3] as Dictionary).ready))
	await create_timer(0.14).timeout
	assert(bool(first.active), "RepeatCount ended before two full cycles")
	await create_timer(0.12).timeout
	assert(not bool(first.active) and not sprite.visible and int(manager.get("_active_count")) == 0)
	assert(float(first.remaining) >= 6.0 and float(first.remaining) <= 18.0)
	manager.set("only_when_on_screen", true)
	first.rect = Rect2(Vector2(100000, 100000), Vector2(24, 32))
	first.remaining = 0.0
	manager.call("_process", 0.1)
	assert(not bool(first.active), "An offscreen area started animating")
	manager.free()
	assert(change_scene_to_file("res://scenes/dungeon/ldtk_arena.tscn") == OK)
	await create_timer(0.55).timeout
	assert(current_scene.has_node("AmbientAreas"))
	assert(current_scene.get_node("AmbientAreas").find_children("*", "CollisionObject2D", true, false).is_empty())
	print("LDTK AMBIENT PASS: empty art, outside-canvas areas, offsets, random delays, chance/enabled, binding, finite animation cycles, cooldown, offscreen culling, no physics, arena integration")
	quit()
