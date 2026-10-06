extends RefCounted
## Physical footprints and coherent depth groups for the authored LDtk palette.

const FEET_OFFSET: float = 8.0
var _units: Dictionary = {}
var _images: Dictionary = {}
var _textures: Dictionary = {}
var _floor: Dictionary = {}
var _root: Node2D
var _arena: Node2D
var _definitions: Dictionary = {}


func build(arena: Node2D, layers: Array, definitions: Dictionary, floor_cells: Dictionary, texture_source: RefCounted = null) -> void:
	_arena = arena
	_floor = floor_cells
	_definitions = definitions
	_root = Node2D.new()
	_root.name = "MapVolumes"
	_root.z_index = 0
	_root.y_sort_enabled = true
	arena.add_child(_root)
	var ordered: Array = layers.duplicate()
	ordered.reverse()
	for layer: Dictionary in ordered:
		var layer_name: String = str(layer.get("__identifier", ""))
		if layer_name == "Collisions":
			_build_intgrid(layer)
		if not layer_name.begins_with("Walls") and not layer_name.begins_with("Objects"):
			continue
		var source_id: int = int(layer.get("__tilesetDefUid", -1))
		if not definitions.has(source_id):
			continue
		if not _textures.has(source_id):
			var definition: Dictionary = definitions[source_id]
			var texture: Texture2D = texture_source.call("get_texture", str(definition.relPath)) as Texture2D if texture_source != null else load("res://" + str(definition.relPath)) as Texture2D
			if texture == null:
				push_error("Sprite LDtk ausente: " + str(definition.relPath))
				continue
			_textures[source_id] = texture
			_images[source_id] = texture_source.call("get_source_image", str(definition.relPath)) if texture_source != null else texture.get_image()
		var tiles: Array = layer.get("autoLayerTiles", []).duplicate()
		tiles.append_array(layer.get("gridTiles", []))
		for tile: Dictionary in tiles:
			_add_tile(tile, layer, source_id)
	for unit: Dictionary in _units.values():
		_finish_unit(unit)


func _add_tile(tile: Dictionary, layer: Dictionary, source_id: int) -> void:
	var source: Vector2i = Vector2i(int(tile.src[0]), int(tile.src[1]))
	var definition: Dictionary = _definitions[source_id]
	var grid: int = int(definition.get("tileGridSize", 16))
	var image: Image = _images[source_id]
	var used: Rect2i = image.get_region(Rect2i(source, Vector2i(grid, grid))).get_used_rect()
	if not used.has_area():
		return
	var pixel: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1]))
	pixel += Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
	var kind: String = "decoration"
	var origin: Vector2 = pixel
	var bounds_pixel: Vector2 = pixel
	var source_path: String = str(definition.get("relPath", ""))
	var semantic_source: Vector2i = source
	if source_path.ends_with("wall/wall_tileset.png") and grid == 8:
		# The editor can cut an existing 16px wall tile into four 8px pieces.
		# Keep its original depth group and physical footprint; only its draw
		# regions become smaller. This also retains the previous flip semantics.
		var source_offset: Vector2i = Vector2i(source.x % 16, source.y % 16)
		var world_offset: Vector2i = source_offset
		var flip: int = int(tile.get("f", 0))
		if (flip & 1) != 0:
			world_offset.x = 8 - world_offset.x
		if (flip & 2) != 0:
			world_offset.y = 8 - world_offset.y
		origin -= Vector2(world_offset)
		bounds_pixel = origin + Vector2(source_offset)
		semantic_source -= source_offset
	if source_path.ends_with("column_square.png") or source_path.ends_with("column_round.png"):
		kind = "column_square" if source_path.ends_with("column_square.png") else "column_round"
		origin -= Vector2(source.x % 32, source.y)
	elif source_path.ends_with("wall/wall_tileset.png"):
		if semantic_source.y == 176 and semantic_source.x in [0, 160]:
			kind = "side"
		elif semantic_source.x >= 176 and semantic_source.y >= 16 and (semantic_source.y - 16) % 64 < 48:
			kind = "wall" if semantic_source.x >= 192 else "trim"
			origin.y -= (semantic_source.y - 16) % 64
		elif semantic_source.y >= 128 and semantic_source.y < 176 and semantic_source.x < 176:
			kind = "wall"
			origin.y -= semantic_source.y - 128
		elif semantic_source.y >= 208 and semantic_source.y < 256 and semantic_source.x < 176:
			kind = "wall"
			origin.y -= semantic_source.y - 208
		elif semantic_source.y >= 64 and semantic_source.y < 112 and semantic_source.x < 176:
			kind = "wall"
			origin.y -= semantic_source.y - 64
		elif semantic_source.y >= 16 and semantic_source.y < 64 and semantic_source.x < 176:
			kind = "wall"
			origin.y -= semantic_source.y - 16
	elif source_id == 105 and source.x < 64 and source.y < 64:
		kind = "column_square" if source.x < 32 else "column_round"
		origin -= Vector2(source.x % 32, source.y)
	elif source_id == 103:
		if source.y == 320 and source.x in [48, 64]:
			kind = "side"
		elif source.y < 256 and source.x <= 160 and source.y % 64 < 48:
			kind = "wall" if source.x < 160 else "trim"
			origin.y -= source.y % 64
		elif source.y >= 256 and source.y < 304:
			kind = "wall"
			origin.y -= source.y - 256
		elif source.y >= 320 and source.x < 48:
			kind = "wall"
			origin.y -= source.y - 320
	# Back walls must not cover authored props with a lower Y baseline.
	# Props retain the player's depth band, so walking behind/front still works.
	var depth_band: int = 1 if str(layer.get("__identifier", "")) == "WallsBack" else 2
	var key: String = "%s:%s:%s" % [depth_band, kind, origin]
	if not _units.has(key):
		var node: Node2D = Node2D.new()
		node.z_index = depth_band
		node.name = kind + "_" + str(_units.size())
		_arena.add_child(node)
		node.add_to_group("ldtk_map_volumes")
		_units[key] = {"node": node, "kind": kind, "origin": origin, "bounds": Rect2(bounds_pixel + Vector2(used.position), Vector2(used.size))}
	var unit: Dictionary = _units[key]
	var bounds: Rect2 = unit.bounds
	unit.bounds = bounds.merge(Rect2(bounds_pixel + Vector2(used.position), Vector2(used.size)))
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = _textures[source_id]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2(source), Vector2(grid, grid))
	sprite.position = pixel
	sprite.flip_h = (int(tile.get("f", 0)) & 1) != 0
	sprite.flip_v = (int(tile.get("f", 0)) & 2) != 0
	(unit.node as Node2D).add_child(sprite)


func _finish_unit(unit: Dictionary) -> void:
	var node: Node2D = unit.node
	var kind: String = unit.kind
	var origin: Vector2 = unit.origin
	var bounds: Rect2 = unit.bounds
	var footprint: Rect2 = Rect2()
	var baseline: float = bounds.end.y
	if kind.begins_with("column"):
		baseline = origin.y + 54.0
		footprint = Rect2(origin + Vector2(9.0 if kind == "column_square" else 10.0, 46.0), Vector2(15.0 if kind == "column_square" else 12.0, 8.0))
	elif kind == "side":
		footprint = bounds
	elif kind == "wall" or kind == "trim":
		# A south perimeter projects its face OUTSIDE the floor; other faces
		# rise above their supporting base, including interior partitions.
		var floor_below: bool = _has_floor_near(origin + Vector2(8.0, 49.0))
		var floor_above: bool = _has_floor_near(origin + Vector2(8.0, -1.0))
		var south: bool = not floor_below and floor_above
		baseline = origin.y + (0.0 if south else 48.0)
		if kind == "wall" and bounds.size.x > 1.0:
			footprint = Rect2(Vector2(bounds.position.x, origin.y + (0.0 if south else 40.0)), Vector2(bounds.size.x, 8.0))
		# Junctions carry a lateral support across the projected face.
		# Continuous LE/LD tiles and floor containment close the outer sides.
	node.position = Vector2(0.0, baseline - FEET_OFFSET)
	for child: Node in node.get_children():
		(child as Node2D).position -= node.position
	node.set_meta("kind", kind)
	node.set_meta("authored_origin", origin)
	node.set_meta("footprint", footprint)
	if footprint.has_area():
		_add_body(node, footprint, "Footprint", false)


func _has_floor_near(point: Vector2) -> bool:
	for offset: float in [-16.0, 0.0, 16.0]:
		var cell: Vector2i = Vector2i(floori((point.x + offset) / 16.0), floori(point.y / 16.0))
		if _floor.has(cell):
			return true
	return false


func _add_body(parent: Node2D, rect: Rect2, body_name: String, disabled: bool) -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = shape
	collider.disabled = disabled
	collider.position = rect.get_center() - parent.position
	body.add_child(collider)
	parent.add_child(body)


func _build_intgrid(layer: Dictionary) -> void:
	var values: Array = layer.get("intGridCsv", [])
	var width: int = int(layer.get("__cWid", 1))
	var grid: int = int(layer.get("__gridSize", 16))
	var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
	for index: int in range(values.size()):
		var value: int = int(values[index])
		if value == 0:
			continue
		var position: Vector2 = Vector2(index % width, floori(float(index) / width)) * grid + offset
		# Doors are open in this enemy-free preview. Hazard marks a no-walk
		# boundary, without adding damage or a new combat mechanic.
		_add_body(_root, Rect2(position, Vector2(grid, grid)), "DoorBlock" if value == 2 else "GridSolid", value == 2)
