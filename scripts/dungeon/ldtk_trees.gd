extends Node2D
## Tree stamps: a small solid root footprint and one coherent Y-sorted visual.

const SOURCE_SIZE: Vector2 = Vector2(80, 80)
const ROOT_CENTER: Vector2 = Vector2(40, 70)
const ROOT_WIDTH: float = 24.0
const ROOT_HEIGHT: float = 12.0
const BASELINE: Vector2 = Vector2(40, 74)
const ACTOR_FEET_OFFSET: float = 8.0
const ACTOR_Z: int = 2
const PALETTE: ShaderMaterial = preload("res://resources/visual/terrain/tree_palette.tres")
const CROWN_RGBA: Array[int] = [0xe85e54ff, 0xad3f52ff, 0x782b55ff, 0x4f264dff, 0x1c213dff]
var _crown_masks: Dictionary[String, Image] = {}
var _crown_centers: Dictionary[String, Vector2] = {}
var _source_hashes: Dictionary[String, String] = {}
var _shape_cache: Dictionary[String, Array] = {}


static func is_tree_source(definition: Dictionary) -> bool:
	return str(definition.get("relPath", "")).replace("\\", "/").ends_with("/tree.png")


func build(layers: Array, definitions: Dictionary, textures: RefCounted, height_query: Callable = Callable()) -> void:
	y_sort_enabled = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var patches: Dictionary[String, Dictionary] = {}
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var source_id: int = int(layer.get("__tilesetDefUid", -1)) if layer.get("__tilesetDefUid") != null else -1
		if not definitions.has(source_id) or not is_tree_source(definitions[source_id] as Dictionary):
			continue
		var path: String = str((definitions[source_id] as Dictionary).get("relPath", ""))
		var texture: Texture2D = textures.call("get_texture", path) as Texture2D
		var image: Image = textures.call("get_source_image", path) as Image
		if texture == null or image == null or Vector2(image.get_size()) != SOURCE_SIZE:
			push_error("Tree mapping expects the authored 80x80 tree.png: " + path)
			continue
		_prepare_crown(path, image)
		var grid: int = int(layer.get("__gridSize", 16))
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		var bounds: Rect2 = Rect2(offset, Vector2(float(layer.get("__cWid", 0)), float(layer.get("__cHei", 0))) * grid)
		var occupied: Array[Vector2] = []
		for y: int in range(0, int(SOURCE_SIZE.y), grid):
			for x: int in range(0, int(SOURCE_SIZE.x), grid):
				var sample: Vector2 = Vector2(x, y)
				if image.get_region(Rect2i(Vector2i(sample), Vector2i.ONE * grid)).get_used_rect().has_area():
					occupied.append(sample)
		var tiles: Array = (layer.get("autoLayerTiles", []) as Array).duplicate()
		tiles.append_array(layer.get("gridTiles", []))
		for tile: Dictionary in tiles:
			var source: Vector2 = Vector2(float(tile.src[0]), float(tile.src[1]))
			var used: Rect2i = image.get_region(Rect2i(Vector2i(source), Vector2i.ONE * grid)).get_used_rect()
			if not used.has_area():
				continue
			var pixel: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1])) + offset
			var flip: int = int(tile.get("f", 0))
			var stamp_source: Vector2 = source
			if (flip & 1) != 0:
				stamp_source.x = SOURCE_SIZE.x - float(grid) - source.x
			if (flip & 2) != 0:
				stamp_source.y = SOURCE_SIZE.y - float(grid) - source.y
			var origin: Vector2 = pixel - stamp_source
			var key: String = "%s:%s:%s" % [layer.get("iid", layer.get("__identifier", "")), origin, flip]
			if not patches.has(key):
				patches[key] = {"origin": origin, "flip": flip, "sprites": [], "painted": [],
					"bounds": bounds, "occupied": occupied, "grid": grid, "texture": texture, "source_path": path}
			var patch: Dictionary = patches[key]
			(patch.painted as Array).append(Rect2(pixel, Vector2.ONE * grid))
			var sprite: Sprite2D = Sprite2D.new()
			sprite.texture = texture
			sprite.material = PALETTE
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_rect = Rect2(source, Vector2.ONE * grid)
			sprite.position = pixel
			sprite.flip_h = (flip & 1) != 0
			sprite.flip_v = (flip & 2) != 0
			sprite.modulate.a = float(tile.get("a", 1)) * float(layer.get("__opacity", 1))
			(patch.sprites as Array).append(sprite)
	for patch: Dictionary in patches.values():
		_complete_stamp(patch)
		_finish_tree(patch, height_query)


func _complete_stamp(patch: Dictionary) -> void:
	# LDtk clips a stamp to its level. Only restore missing cells beyond that
	# boundary: an intentionally erased cell inside the level stays erased.
	var origin: Vector2 = patch.origin as Vector2
	var flip: int = int(patch.flip)
	var grid: int = int(patch.grid)
	var bounds: Rect2 = patch.bounds as Rect2
	var outside: bool = false
	var sprites: Array = patch.sprites as Array
	var opacity: float = (sprites[0] as Sprite2D).modulate.a
	for sprite: Sprite2D in sprites:
		if not is_equal_approx(sprite.modulate.a, opacity): return
	for source: Vector2 in patch.occupied:
		var mirrored: Vector2 = source
		if (flip & 1) != 0: mirrored.x = SOURCE_SIZE.x - float(grid) - source.x
		if (flip & 2) != 0: mirrored.y = SOURCE_SIZE.y - float(grid) - source.y
		var point: Vector2 = origin + mirrored + Vector2.ONE * float(grid) * 0.5
		var painted: bool = false
		for rect: Rect2 in patch.painted:
			painted = painted or rect.has_point(point)
		if painted: continue
		if not bounds.has_area() or bounds.has_point(point): return
		outside = true
	for sprite: Sprite2D in sprites: sprite.free()
	var whole: Sprite2D = Sprite2D.new()
	whole.texture = patch.texture as Texture2D
	whole.material = PALETTE
	whole.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	whole.centered = false
	whole.position = origin
	whole.flip_h = (flip & 1) != 0
	whole.flip_v = (flip & 2) != 0
	whole.modulate.a = opacity
	patch.sprites = [whole]
	patch.whole_stamp = true
	patch.boundary_completed = outside
	patch.painted = [Rect2(origin, SOURCE_SIZE)]


static func flip_point(point: Vector2, flip: int) -> Vector2:
	return Vector2(SOURCE_SIZE.x - point.x if (flip & 1) != 0 else point.x,
		SOURCE_SIZE.y - point.y if (flip & 2) != 0 else point.y)


func shadow_descriptions() -> Array[Dictionary]:
	var casters: Array[Dictionary] = []
	for tree: Node2D in get_children():
		var opacity: float = 0.0
		for child: Node in tree.get_children():
			var sprite: Sprite2D = child as Sprite2D
			if sprite == null or not sprite.visible or sprite.modulate.a <= 0.0: continue
			opacity = maxf(opacity, sprite.modulate.a)
		if opacity <= 0.0: continue
		var crowns: Array = tree.get_meta(&"shadow_crowns", []) as Array
		var primary: PackedVector2Array = PackedVector2Array()
		for polygon: PackedVector2Array in crowns:
			if polygon.size() > primary.size(): primary = polygon
		var height: float = float(tree.get_meta(&"projected_height", 0.0))
		var footprint: Rect2 = tree.get_meta(&"footprint") as Rect2
		casters.append({"anchor": footprint.get_center() - Vector2(0, height),
			"crown": primary, "crowns": crowns, "crown_center": tree.get_meta(&"shadow_crown_center", Vector2.ZERO),
			"crown_height": 48.0, "terrain_height": height, "contact_enabled": tree.has_node("Trunk"),
			"source_hash": tree.get_meta(&"shadow_source_hash", ""), "scale": Vector2.ONE, "weight": opacity})
	return casters


func _prepare_crown(path: String, image: Image) -> void:
	if _crown_masks.has(path): return
	var mask: Image = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	mask.fill(Color.TRANSPARENT)
	# Fill only tiny internal gaps in each foliage row. The four brown trunk
	# colours never become canopy, including where roots overlap the fringe.
	for y: int in range(80):
		var left: int = 80
		var right: int = -1
		for x: int in range(80):
			if image.get_pixel(x, y).to_rgba32() in CROWN_RGBA:
				left = mini(left, x)
				right = maxi(right, x)
		for x: int in range(left, right + 1): mask.set_pixel(x, y, Color.WHITE)
	_crown_masks[path] = mask
	_crown_centers[path] = Rect2(mask.get_used_rect()).get_center()
	_source_hashes[path] = image.get_data().hex_encode().sha256_text()


func _shadow_polygons(patch: Dictionary) -> Array:
	var path: String = str(patch.source_path)
	var origin: Vector2 = patch.origin as Vector2
	var flip: int = int(patch.flip)
	var visible_rects: Array[Rect2] = []
	for sprite: Sprite2D in patch.sprites:
		if sprite.modulate.a <= 0.0: continue
		visible_rects.append(Rect2(sprite.position - origin, sprite.get_rect().size))
	visible_rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y if a.position.y != b.position.y else a.position.x < b.position.x)
	var key: String = var_to_str([path, flip, visible_rects])
	if _shape_cache.has(key): return _shape_cache[key]
	var base: Image = _crown_masks[path]
	var mask: Image = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	mask.fill(Color.TRANSPARENT)
	for y: int in range(80):
		for x: int in range(80):
			if base.get_pixel(x, y).a <= 0.0: continue
			var local: Vector2 = flip_point(Vector2(x + 0.5, y + 0.5), flip)
			for rect: Rect2 in visible_rects:
				if rect.has_point(local):
					mask.set_pixel(x, y, Color.WHITE)
					break
	var bitmap: BitMap = BitMap.new()
	bitmap.create_from_image_alpha(mask)
	var contours: Array[PackedVector2Array] = bitmap.opaque_to_polygons(Rect2i(0, 0, 80, 80), 2.0)
	var polygons: Array[PackedVector2Array] = []
	var root: Vector2 = flip_point(ROOT_CENTER, flip)
	for contour: PackedVector2Array in contours:
		var polygon: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in contour: polygon.append(flip_point(point, flip) - root)
		if polygon.size() >= 3: polygons.append(polygon)
	_shape_cache[key] = polygons
	return polygons


func _finish_tree(patch: Dictionary, height_query: Callable) -> void:
	var origin: Vector2 = patch.origin as Vector2
	var flip: int = int(patch.flip)
	var anchor: Vector2 = origin + flip_point(BASELINE, flip)
	var root_center: Vector2 = origin + flip_point(ROOT_CENTER, flip)
	var tree: Node2D = Node2D.new()
	tree.name = "Tree_%d" % get_child_count()
	tree.z_index = ACTOR_Z
	tree.z_as_relative = false
	tree.position = anchor - Vector2(0, ACTOR_FEET_OFFSET)
	tree.set_meta(&"authored_origin", origin)
	tree.set_meta(&"footprint", Rect2(root_center - Vector2(ROOT_WIDTH, ROOT_HEIGHT) * 0.5, Vector2(ROOT_WIDTH, ROOT_HEIGHT)))
	tree.set_meta(&"depth_baseline", anchor.y)
	tree.set_meta(&"whole_stamp", bool(patch.get("whole_stamp", false)))
	tree.set_meta(&"boundary_completed", bool(patch.get("boundary_completed", false)))
	add_child(tree)
	tree.add_to_group(&"ldtk_trees")
	var projected_height: float = roundf(float(height_query.call(to_global(anchor)))) if height_query.is_valid() else 0.0
	tree.set_meta(&"projected_height", projected_height)
	var source_path: String = str(patch.source_path)
	tree.set_meta(&"shadow_crowns", _shadow_polygons(patch))
	tree.set_meta(&"shadow_crown_center", flip_point(_crown_centers[source_path], flip) - flip_point(ROOT_CENTER, flip))
	tree.set_meta(&"shadow_source_hash", _source_hashes[source_path])
	for sprite: Sprite2D in patch.sprites:
		sprite.position -= tree.position + Vector2(0, projected_height)
		tree.add_child(sprite)
	# A canopy-only selection must not create an invisible solid trunk.
	var root_painted: bool = false
	for rect: Rect2 in patch.painted:
		root_painted = root_painted or rect.has_point(root_center)
	if not root_painted:
		return
	var solid: StaticBody2D = StaticBody2D.new()
	solid.name = "Trunk"
	solid.collision_layer = 1
	solid.collision_mask = 0
	solid.position = root_center - tree.position
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = ROOT_HEIGHT * 0.5
	capsule.height = ROOT_WIDTH
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.name = "RootFootprint"
	collider.shape = capsule
	collider.rotation = PI * 0.5
	solid.add_child(collider)
	tree.add_child(solid)
