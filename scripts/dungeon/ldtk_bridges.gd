extends Node2D
## Classify the authored atlas before terrain support is built. Complete stamps
## can live in any bridge layer; rails and wet masonry keep their own depth.

const CONTACT_SHADER: Shader = preload("res://shaders/bridge_submersion.gdshader")
const PARTS: Array[String] = ["Bridge_BackRail", "Bridge_FrontRail", "Bridge_Facade"]
var bridges: Array[Node2D] = []
var contact_materials: Array[ShaderMaterial] = []
var water_elapsed: float = 0.0
var _water: Node = null


static func prepare_layers(layers: Array, definitions: Dictionary) -> Array:
	var prepared: Array = []
	var parts: Dictionary[String, Dictionary] = {}
	var has_paint: bool = false
	for layer: Dictionary in layers:
		var source_id: int = int(layer.get("__tilesetDefUid", -1)) if layer.get("__tilesetDefUid") != null else -1
		var definition: Dictionary = definitions.get(source_id, {}) as Dictionary
		var path: String = str(definition.get("relPath", "")).replace("\\", "/")
		if not path.ends_with("/bridge_all.png"):
			prepared.append(layer)
			continue
		if not bool(layer.get("visible", true)):
			continue
		var tiles: Array = (layer.get("autoLayerTiles", []) as Array).duplicate()
		tiles.append_array(layer.get("gridTiles", []))
		var offset: Vector2i = Vector2i(int(layer.get("__pxTotalOffsetX", 0)), int(layer.get("__pxTotalOffsetY", 0)))
		for original: Dictionary in tiles:
			var source: Array = original.get("src", []) as Array
			var point: Array = original.get("px", []) as Array
			if source.size() < 2 or point.size() < 2:
				continue
			# bridge_all 144x112: rear rail y=0; deck y=16/32;
			# front rail y=48; lower supports y=64/80/96.
			var source_y: int = int(source[1])
			var part_name: String = "Floor_Bridges" if source_y in [16, 32] else "Bridge_BackRail" if source_y == 0 else "Bridge_FrontRail" if source_y == 48 else "Bridge_Facade"
			if not parts.has(part_name):
				var part: Dictionary = layer.duplicate()
				part["__identifier"] = part_name
				part["gridTiles"] = []
				part["autoLayerTiles"] = []
				part["__opacity"] = 1.0
				for key: String in ["pxOffsetX", "pxOffsetY", "__pxTotalOffsetX", "__pxTotalOffsetY"]:
					part[key] = 0
				parts[part_name] = part
			var tile: Dictionary = original.duplicate()
			tile["px"] = [int(point[0]) + offset.x, int(point[1]) + offset.y]
			tile["a"] = float(tile.get("a", 1.0)) * float(layer.get("__opacity", 1.0))
			(parts[part_name]["gridTiles"] as Array).append(tile)
			has_paint = true
	if not has_paint:
		return layers
	for part_name: String in ["Floor_Bridges", "Bridge_BackRail", "Bridge_FrontRail", "Bridge_Facade"]:
		if parts.has(part_name):
			prepared.append(parts[part_name])
	return prepared


static func is_bridge_decoration(layer_name: String) -> bool:
	return layer_name in PARTS


func build(layers: Array, definitions: Dictionary, textures: RefCounted, water: Node, ground_query: Callable, cloud_material: ShaderMaterial = null) -> void:
	y_sort_enabled = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_water = water
	var parts: Dictionary[String, Array] = {}
	var deck_cells: Dictionary[Vector2i, bool] = {}
	var atlas_path: String = ""
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)): continue
		var name_text: String = str(layer.get("__identifier", ""))
		var source_id: int = int(layer.get("__tilesetDefUid", -1)) if layer.get("__tilesetDefUid") != null else -1
		var definition: Dictionary = definitions.get(source_id, {}) as Dictionary
		var path: String = str(definition.get("relPath", ""))
		if not path.ends_with("/bridge_all.png"): continue
		atlas_path = path
		var tiles: Array = (layer.get("gridTiles", []) as Array).duplicate()
		tiles.append_array(layer.get("autoLayerTiles", []))
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		if name_text == "Floor_Bridges":
			for tile: Dictionary in tiles:
				var point: Vector2 = Vector2(float(tile.px[0]), float(tile.px[1])) + offset
				deck_cells[Vector2i((point / 16.0).floor())] = true
		elif is_bridge_decoration(name_text):
			parts[name_text] = []
			for original: Dictionary in tiles:
				var tile: Dictionary = original.duplicate()
				tile["point"] = Vector2(float(tile.px[0]), float(tile.px[1])) + offset
				tile["a"] = float(tile.get("a", 1.0)) * float(layer.get("__opacity", 1.0))
				(parts[name_text] as Array).append(tile)
	if deck_cells.is_empty():
		set_process(false)
		return
	var atlas: Texture2D = textures.call("get_texture", atlas_path) as Texture2D
	var image: Image = textures.call("get_source_image", atlas_path) as Image
	while not deck_cells.is_empty():
		var first: Vector2i = deck_cells.keys()[0] as Vector2i
		var queue: Array[Vector2i] = [first]
		var bounds: Rect2 = Rect2(Vector2(first * 16), Vector2.ONE * 16)
		deck_cells.erase(first)
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back() as Vector2i
			bounds = bounds.merge(Rect2(Vector2(cell * 16), Vector2.ONE * 16))
			for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var neighbor: Vector2i = cell + direction
				if deck_cells.erase(neighbor): queue.append(neighbor)
		_add_bridge(bounds, parts, atlas, image, ground_query, cloud_material)
	set_process(_water != null and not contact_materials.is_empty())
	if _water != null: set_elapsed(float(_water.get("elapsed")))


func _add_bridge(deck: Rect2, parts: Dictionary[String, Array], atlas: Texture2D, image: Image, ground_query: Callable, cloud_material: ShaderMaterial) -> void:
	var unit: Node2D = Node2D.new()
	unit.name = "Bridge_%d" % bridges.size()
	unit.y_sort_enabled = true
	unit.set_meta(&"deck_rect", deck)
	unit.set_meta(&"source_atlas", "res://assets/bridge/bridge_all.png")
	add_child(unit)
	var rail_rects: Array[Rect2] = [Rect2(deck.position + Vector2(2, -3), Vector2(deck.size.x - 4, 3)), Rect2(Vector2(deck.position.x + 2, deck.end.y), Vector2(deck.size.x - 4, 4))]
	unit.set_meta(&"rail_rects", rail_rects)
	var solid: StaticBody2D = StaticBody2D.new()
	solid.name = "Solid"
	solid.collision_layer = 1
	solid.collision_mask = 0
	unit.add_child(solid)
	for rect: Rect2 in rail_rects:
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = rect.size
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.shape = shape
		collider.position = rect.get_center()
		solid.add_child(collider)
	var facade_tiles: Array = []
	var facade_bounds: Rect2 = Rect2()
	for part_name: String in PARTS:
		var rail: Node2D = null
		if part_name != "Bridge_Facade":
			rail = Node2D.new()
			rail.name = "BackRail" if part_name == "Bridge_BackRail" else "FrontRail"
			rail.position.y = deck.position.y - 8.0 if part_name == "Bridge_BackRail" else deck.end.y + 8.0
			rail.z_index = 2
			rail.z_as_relative = false
			unit.add_child(rail)
		for tile: Dictionary in parts.get(part_name, []):
			var point: Vector2 = tile.point as Vector2
			var expected_y: float = deck.position.y - 16.0 if part_name == "Bridge_BackRail" else deck.end.y
			var matches: bool = point.x >= deck.position.x and point.x < deck.end.x and (point.y == expected_y if part_name != "Bridge_Facade" else point.y >= deck.end.y + 16.0 and point.y < deck.end.y + 48.0)
			if not matches: continue
			if rail != null:
				var sprite: Sprite2D = Sprite2D.new()
				sprite.texture = atlas
				sprite.centered = false
				sprite.region_enabled = true
				sprite.region_rect = Rect2(Vector2(float(tile.src[0]), float(tile.src[1])), Vector2.ONE * 16)
				sprite.position = point - rail.position
				sprite.flip_h = (int(tile.get("f", 0)) & 1) != 0
				sprite.flip_v = (int(tile.get("f", 0)) & 2) != 0
				sprite.modulate.a = float(tile.get("a", 1.0))
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				sprite.material = cloud_material
				rail.add_child(sprite)
			else:
				facade_tiles.append(tile)
				var rect: Rect2 = Rect2(point, Vector2.ONE * 16)
				facade_bounds = rect if not facade_bounds.has_area() else facade_bounds.merge(rect)
	unit.set_meta(&"facade_bounds", facade_bounds)
	if facade_bounds.has_area(): _add_facade(unit, facade_tiles, facade_bounds, image, ground_query, cloud_material)
	bridges.append(unit)


func _add_facade(unit: Node2D, tiles: Array, bounds: Rect2, atlas: Image, ground_query: Callable, cloud_material: ShaderMaterial) -> void:
	var picture: Image = Image.create(int(bounds.size.x), int(bounds.size.y), false, Image.FORMAT_RGBA8)
	picture.fill(Color.TRANSPARENT)
	for tile: Dictionary in tiles:
		var patch: Image = atlas.get_region(Rect2i(Vector2i(int(tile.src[0]), int(tile.src[1])), Vector2i(16, 16)))
		if (int(tile.get("f", 0)) & 1) != 0: patch.flip_x()
		if (int(tile.get("f", 0)) & 2) != 0: patch.flip_y()
		var opacity: float = float(tile.get("a", 1.0))
		if opacity < 1.0:
			for y: int in range(16):
				for x: int in range(16):
					var color: Color = patch.get_pixel(x, y)
					color.a *= opacity
					patch.set_pixel(x, y, color)
		picture.blend_rect(patch, Rect2i(Vector2i.ZERO, Vector2i(16, 16)), Vector2i((tile.point as Vector2) - bounds.position))
	var mask: Image = Image.create(ceili(bounds.size.x / 4.0), ceili(bounds.size.y / 4.0), false, Image.FORMAT_R8)
	for y: int in range(mask.get_height()):
		for x: int in range(mask.get_width()):
			var point: Vector2 = to_global(bounds.position + Vector2(x * 4 + 2, y * 4 + 2))
			var is_water: bool = _water != null and ground_query.is_valid() and not bool(ground_query.call(point))
			mask.set_pixel(x, y, Color.WHITE if is_water else Color.BLACK)
	var contact: ShaderMaterial = ShaderMaterial.new()
	contact.shader = CONTACT_SHADER
	contact.set_shader_parameter(&"water_mask", ImageTexture.create_from_image(mask))
	contact.set_shader_parameter(&"waterline_y", to_global(bounds.position + Vector2(0, 16)).y)
	if cloud_material != null:
		for parameter: StringName in [&"enabled", &"brightness", &"saturation", &"contrast"]:
			contact.set_shader_parameter(parameter, cloud_material.get_shader_parameter(parameter))
	if _water != null:
		var profile: Resource = _water.get("profile") as Resource if not _water is WaterSurface else null
		if _water is WaterSurface and not (_water.get("regions") as Array).is_empty():
			var region: Node2D = (_water.get("regions") as Array)[0] as Node2D
			var preset: String = str(region.get_meta(&"preset", "River"))
			for candidate: WaterProfile in (_water as WaterSurface).profiles:
				if str(candidate.preset_id) == preset: profile = candidate
		if profile != null:
			contact.set_shader_parameter(&"water_tint", profile.get("mid_color"))
			contact.set_shader_parameter(&"flow_direction", profile.get("flow_direction"))
			contact.set_shader_parameter(&"flow_speed", profile.get("flow_speed_px_s"))
	var facade: Sprite2D = Sprite2D.new()
	facade.name = "Facade"
	facade.centered = false
	facade.texture = ImageTexture.create_from_image(picture)
	facade.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	facade.position = bounds.position
	facade.material = contact
	facade.z_index = -35
	facade.z_as_relative = false
	facade.set_meta(&"water_mask", mask)
	unit.add_child(facade)
	contact_materials.append(contact)


func set_elapsed(seconds: float) -> void:
	if not is_finite(seconds): return
	water_elapsed = maxf(seconds, 0.0)
	for contact: ShaderMaterial in contact_materials:
		contact.set_shader_parameter(&"water_elapsed", water_elapsed)


func _process(_delta: float) -> void:
	if is_instance_valid(_water): set_elapsed(float(_water.get("elapsed")))
