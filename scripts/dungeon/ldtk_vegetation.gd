extends Node2D
## Solid lower bushes and reactive grass. Grass shares one player query;
## bushes use static footprints with an eight-pixel upper passage.

const GRASS: Script = preload("res://scripts/visual/reactive_grass.gd")
const BUSH_PALETTE: ShaderMaterial = preload("res://resources/visual/terrain/tree_palette.tres")
const BUCKET_SIZE: float = 32.0
const FEET_OFFSET: Vector2 = Vector2(0, 8)
const BUSH_FOOTPRINT: Rect2 = Rect2(2, 8, 28, 24)
var bushes: Array[Node2D] = []
var grasses: Array[Node2D] = []
var _buckets: Dictionary[Vector2i, Array] = {}
var _touching: Dictionary[int, bool] = {}
var _player: Node2D = null
var _previous_feet: Vector2 = Vector2.ZERO
var _frames: SpriteFrames = null
var _bush_shape: CapsuleShape2D = null


static func is_vegetation_source(definition: Dictionary) -> bool:
	var path: String = str(definition.get("relPath", "")).replace("\\", "/")
	return path.ends_with("/bush.png") or path.ends_with("/grass_animated1.png")


func build(layers: Array, definitions: Dictionary, textures: RefCounted, height_query: Callable = Callable()) -> void:
	y_sort_enabled = true
	set_physics_process(false)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var patches: Dictionary[String, Dictionary] = {}
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)): continue
		var source_id: int = int(layer.get("__tilesetDefUid", -1)) if layer.get("__tilesetDefUid") != null else -1
		var definition: Dictionary = definitions.get(source_id, {}) as Dictionary
		if not is_vegetation_source(definition): continue
		var path: String = str(definition.relPath)
		var texture: Texture2D = textures.call("get_texture", path) as Texture2D
		if texture == null: continue
		var is_grass: bool = path.ends_with("/grass_animated1.png")
		var grid: int = int(layer.get("__gridSize", 16))
		var extent: float = 16.0 if is_grass else 32.0
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		var tiles: Array = (layer.get("autoLayerTiles", []) as Array).duplicate()
		tiles.append_array(layer.get("gridTiles", []))
		for tile: Dictionary in tiles:
			var source: Vector2 = Vector2(float(tile.src[0]), float(tile.src[1]))
			var pixel: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1])) + offset
			var flip: int = int(tile.get("f", 0))
			var mirrored: Vector2 = source
			if (flip & 1) != 0: mirrored.x = extent - float(grid) - source.x
			if (flip & 2) != 0: mirrored.y = extent - float(grid) - source.y
			var origin: Vector2 = pixel - mirrored
			var opacity: float = float(tile.get("a", 1.0)) * float(layer.get("__opacity", 1.0))
			if opacity <= 0.0: continue
			if is_grass:
				_add_grass(origin, flip, opacity, textures, height_query)
				continue
			var key: String = "%s:%s:%s" % [layer.get("iid", layer.get("__identifier", "")), origin, flip]
			if not patches.has(key):
				patches[key] = {"origin": origin, "sprites": [], "painted": []}
			var sprite: Sprite2D = Sprite2D.new()
			sprite.texture = texture
			sprite.material = BUSH_PALETTE
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(source, Vector2.ONE * grid)
			sprite.position = pixel
			sprite.flip_h = (flip & 1) != 0
			sprite.flip_v = (flip & 2) != 0
			sprite.modulate.a = opacity
			(patches[key].sprites as Array).append(sprite)
			(patches[key].painted as Array).append(Rect2(pixel, Vector2.ONE * grid))
	for patch: Dictionary in patches.values():
		var origin: Vector2 = patch.origin as Vector2
		var plant: Node2D = Node2D.new()
		plant.name = "Bush_%d" % bushes.size()
		plant.position = origin + Vector2(16, 28) - FEET_OFFSET
		plant.z_index = 2
		plant.z_as_relative = false
		plant.set_meta(&"authored_origin", origin)
		plant.set_meta(&"upper_passage_pixels", BUSH_FOOTPRINT.position.y)
		add_child(plant)
		var height: float = float(height_query.call(to_global(origin + Vector2(16, 28)))) if height_query.is_valid() else 0.0
		for sprite: Sprite2D in patch.sprites:
			sprite.position -= plant.position + Vector2(0, height)
			plant.add_child(sprite)
		_add_bush_collision(plant, origin, patch.painted as Array)
		bushes.append(plant)


func _merge_rectangles(rectangles: Array[Rect2]) -> Array[Rect2]:
	var changed: bool = true
	while changed:
		changed = false
		for first: int in range(rectangles.size()):
			for second: int in range(first + 1, rectangles.size()):
				var a: Rect2 = rectangles[first]
				var b: Rect2 = rectangles[second]
				var horizontal: bool = a.position.y == b.position.y and a.size.y == b.size.y and (a.end.x == b.position.x or b.end.x == a.position.x)
				var vertical: bool = a.position.x == b.position.x and a.size.x == b.size.x and (a.end.y == b.position.y or b.end.y == a.position.y)
				if not horizontal and not vertical: continue
				rectangles[first] = a.merge(b)
				rectangles.remove_at(second)
				changed = true
				break
			if changed: break
	return rectangles


func _add_bush_collision(plant: Node2D, origin: Vector2, painted: Array) -> void:
	var footprint: Rect2 = Rect2(origin + BUSH_FOOTPRINT.position, BUSH_FOOTPRINT.size)
	var regions: Array[Rect2] = []
	for part: Rect2 in painted:
		var clipped: Rect2 = footprint.intersection(part)
		if clipped.has_area() and not regions.has(clipped): regions.append(clipped)
	regions = _merge_rectangles(regions)
	if regions.is_empty(): return
	var solid: StaticBody2D = StaticBody2D.new()
	solid.name = "Solid"
	solid.collision_layer = 1
	solid.collision_mask = 0
	plant.add_child(solid)
	var whole: bool = regions.size() == 1 and regions[0].is_equal_approx(footprint)
	var bounds: Rect2 = regions[0]
	for region: Rect2 in regions:
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.name = "LowerBody" + str(solid.get_child_count())
		# Artwork moves up on raised terrain; physics stays on the map plane.
		collider.position = region.get_center() - plant.position
		if whole:
			if _bush_shape == null:
				_bush_shape = CapsuleShape2D.new()
				_bush_shape.radius = BUSH_FOOTPRINT.size.y * 0.5
				_bush_shape.height = BUSH_FOOTPRINT.size.x
			collider.shape = _bush_shape
			collider.rotation = PI * 0.5
		else:
			# Partial/erased stamps never acquire a solid invisible lower half.
			var rectangle: RectangleShape2D = RectangleShape2D.new()
			rectangle.size = region.size
			collider.shape = rectangle
		solid.add_child(collider)
		bounds = bounds.merge(region)
	plant.set_meta(&"footprint", bounds)
	plant.set_meta(&"collision_regions", regions)


func _grass_frames(textures: RefCounted) -> SpriteFrames:
	if _frames != null: return _frames
	var images: Array[Texture2D] = []
	for index: int in range(1, 5):
		var path: String = "assets/tiles/floor/grass_animated%d.png" % index
		var image: Texture2D = textures.call("get_texture", path) as Texture2D
		if image == null: return null
		images.append(image)
	_frames = SpriteFrames.new()
	_frames.remove_animation(&"default")
	_frames.add_animation(&"idle")
	_frames.set_animation_loop(&"idle", false)
	_frames.add_frame(&"idle", images[0])
	_frames.add_animation(&"rustle")
	_frames.set_animation_loop(&"rustle", false)
	_frames.set_animation_speed(&"rustle", 14.0)
	for frame: int in [0, 1, 2, 3, 2, 1, 0]: _frames.add_frame(&"rustle", images[frame])
	return _frames


func _add_grass(origin: Vector2, flip: int, opacity: float, textures: RefCounted, height_query: Callable) -> void:
	var frames: SpriteFrames = _grass_frames(textures)
	if frames == null: return
	var plant: Node2D = GRASS.new() as Node2D
	plant.name = "Grass_%d" % grasses.size()
	plant.position = origin + Vector2(8, 15) - FEET_OFFSET
	plant.z_index = 2
	plant.z_as_relative = false
	add_child(plant)
	var height: float = float(height_query.call(to_global(origin + Vector2(8, 15)))) if height_query.is_valid() else 0.0
	plant.call("configure", frames, origin - plant.position - Vector2(0, height), flip, opacity)
	var contact: Rect2 = Rect2(origin + Vector2(2, 8), Vector2(12, 8)).grow(4.0)
	plant.set_meta(&"contact_rect", contact)
	grasses.append(plant)
	var first: Vector2i = Vector2i((contact.position / BUCKET_SIZE).floor())
	var last: Vector2i = Vector2i((contact.end / BUCKET_SIZE).floor())
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var key: Vector2i = Vector2i(x, y)
			if not _buckets.has(key): _buckets[key] = []
			(_buckets[key] as Array).append(plant)


func bind_player(subject: Node2D) -> void:
	_player = subject
	_previous_feet = to_local(subject.global_position + FEET_OFFSET)
	_touching.clear()
	set_physics_process(not grasses.is_empty())


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player): return
	var feet: Vector2 = to_local(_player.global_position + FEET_OFFSET)
	var distance: float = feet.distance_to(_previous_feet)
	if distance <= 0.001: return
	if distance > 128.0:
		_previous_feet = feet
		_touching.clear()
		return # A warp must not rustle every plant along its teleport line.
	var query: Rect2 = Rect2(_previous_feet.min(feet), (_previous_feet - feet).abs()).grow(16.0)
	var first: Vector2i = Vector2i((query.position / BUCKET_SIZE).floor())
	var last: Vector2i = Vector2i((query.end / BUCKET_SIZE).floor())
	var visited: Dictionary[int, bool] = {}
	var touching_now: Dictionary[int, bool] = {}
	var steps: int = maxi(1, ceili(distance / 4.0))
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			for plant: Node2D in _buckets.get(Vector2i(x, y), []):
				var identity: int = plant.get_instance_id()
				if visited.has(identity): continue
				visited[identity] = true
				var contact: Rect2 = plant.get_meta(&"contact_rect") as Rect2
				if contact.has_point(feet): touching_now[identity] = true
				if _touching.has(identity): continue
				for step: int in range(1, steps + 1):
					if contact.has_point(_previous_feet.lerp(feet, float(step) / float(steps))):
						plant.call("react")
						break
	_touching = touching_now
	_previous_feet = feet
