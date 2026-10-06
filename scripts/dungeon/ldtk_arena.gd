extends Node2D

const MAP_PATH: String = "res://monster_booster.ldtk"
const LEVEL_NAME: String = "RoomTemplate_30x16"
const TRAINING_SCENE: PackedScene = preload("res://scenes/dungeon/merchant_platform.tscn")
const TILE_SIZE: int = 16
const MAP_GEOMETRY: Script = preload("res://scripts/dungeon/ldtk_map_geometry.gd")
const GAMEPLAY: Script = preload("res://scripts/dungeon/ldtk_gameplay.gd")
const TEXTURE_SOURCE: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
const LEAVES: Script = preload("res://scripts/dungeon/ldtk_leaves.gd")
const AMBIENT_AREAS: Script = preload("res://scripts/dungeon/ldtk_ambient_areas.gd")
const BACKGROUND_COLOR: Color = Color("#25131a")

var _floor_cells: Dictionary = {}
var _floor_bounds: Rect2 = Rect2()
var _min_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _max_cell: Vector2i = Vector2i(-2147483647, -2147483647)
@export var map_path: String = MAP_PATH
@export var level_name: String = LEVEL_NAME
var _gameplay: Node2D
var _textures: RefCounted = TEXTURE_SOURCE.new()
var _texture_refresh_remaining: float = 0.0


func _process(delta: float) -> void:
	_texture_refresh_remaining -= delta
	if _texture_refresh_remaining <= 0.0:
		_texture_refresh_remaining = 0.3
		_textures.call("refresh")


func _ready() -> void:
	if not _build_ldtk_level():
		push_error("Nao foi possivel carregar a arena LDtk: " + map_path)
		return
	_build_floor_collisions()
	_add_training_player_and_controls()
	_fade_in()


func _build_ldtk_level() -> bool:
	var map_file: FileAccess = FileAccess.open(map_path, FileAccess.READ)
	if map_file == null:
		return false
	var parsed: Variant = JSON.parse_string(map_file.get_as_text())
	if not parsed is Dictionary:
		return false
	var map_data: Dictionary = parsed
	var level: Dictionary = {}
	for candidate_variant in map_data.get("levels", []):
		var candidate: Dictionary = candidate_variant
		if str(candidate.get("identifier", "")) == level_name:
			level = candidate
			break
	if level.is_empty():
		return false
	var layers_variant: Variant = level.get("layerInstances", [])
	if not layers_variant is Array:
		return false
	var layers: Array = layers_variant
	_gameplay = GAMEPLAY.new() as Node2D
	_gameplay.name = "Gameplay"
	add_child(_gameplay)
	_gameplay.call("configure", layers)
	var tileset_defs: Dictionary = {}
	var definitions: Dictionary = map_data.get("defs", {})
	for definition_variant in definitions.get("tilesets", []):
		var definition: Dictionary = definition_variant
		tileset_defs[int(definition.get("uid", -1))] = definition
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var atlas_sources: Dictionary = {}
	var backdrop: Polygon2D = Polygon2D.new()
	backdrop.name = "Backdrop"
	backdrop.color = BACKGROUND_COLOR
	backdrop.z_index = -100
	var width: float = float(level.get("pxWid", 1520))
	var height: float = float(level.get("pxHei", 928))
	backdrop.polygon = PackedVector2Array([
		Vector2(-512.0, -512.0), Vector2(width + 512.0, -512.0),
		Vector2(width + 512.0, height + 512.0), Vector2(-512.0, height + 512.0)
	])
	add_child(backdrop)
	var map_root: Node2D = Node2D.new()
	map_root.name = "LdtkLayers"
	add_child(map_root)
	for layer_variant in layers:
		var layer: Dictionary = layer_variant
		var tiles: Array = []
		var automatic_variant: Variant = layer.get("autoLayerTiles", [])
		if automatic_variant is Array:
			tiles.append_array(automatic_variant)
		var manual_variant: Variant = layer.get("gridTiles", [])
		if manual_variant is Array:
			tiles.append_array(manual_variant)
		if tiles.is_empty():
			continue
		var layer_name: String = str(layer.get("__identifier", "Layer"))
		if layer_name.begins_with("Walls") or layer_name.begins_with("Objects"):
			continue
		var source_id: int = int(layer.get("__tilesetDefUid", -1))
		if LEAVES.is_leaves_source(tileset_defs.get(source_id, {})):
			continue
		if not atlas_sources.has(source_id):
			var source: TileSetAtlasSource = _make_atlas_source(source_id, tileset_defs, tile_set)
			if source == null:
				push_error("Tileset LDtk ausente na camada " + layer_name)
				return false
			atlas_sources[source_id] = source
		var atlas: TileSetAtlasSource = atlas_sources[source_id]
		var layer_nodes: Array[TileMapLayer] = []
		var stack_counts: Dictionary = {}
		for tile_variant in tiles:
			var tile: Dictionary = tile_variant
			var pixel: Array = tile.get("px", [])
			var source_pixel: Array = tile.get("src", [])
			if pixel.size() < 2 or source_pixel.size() < 2:
				continue
			var cell: Vector2i = Vector2i(floori(float(pixel[0]) / TILE_SIZE), floori(float(pixel[1]) / TILE_SIZE))
			if layer_name == "Floor" and bool(_gameplay.call("is_gap_cell", cell)):
				continue
			var atlas_cell: Vector2i = Vector2i(floori(float(source_pixel[0]) / TILE_SIZE), floori(float(source_pixel[1]) / TILE_SIZE))
			if not atlas.has_tile(atlas_cell):
				atlas.create_tile(atlas_cell)
			var depth: int = int(stack_counts.get(cell, 0))
			stack_counts[cell] = depth + 1
			while layer_nodes.size() <= depth:
				var tile_layer: TileMapLayer = TileMapLayer.new()
				tile_layer.name = layer_name + "_" + str(layer_nodes.size())
				tile_layer.tile_set = tile_set
				tile_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				tile_layer.z_index = _layer_z_index(layer_name) + layer_nodes.size()
				tile_layer.position = Vector2(float(layer.get("pxOffsetX", 0)), float(layer.get("pxOffsetY", 0)))
				map_root.add_child(tile_layer)
				layer_nodes.append(tile_layer)
			var flip_flags: int = 0
			var ld_flip: int = int(tile.get("f", 0))
			if (ld_flip & 1) != 0:
				flip_flags |= TileSetAtlasSource.TRANSFORM_FLIP_H
			if (ld_flip & 2) != 0:
				flip_flags |= TileSetAtlasSource.TRANSFORM_FLIP_V
			layer_nodes[depth].set_cell(cell, source_id, atlas_cell, flip_flags)
			if layer_name == "Floor":
				_floor_cells[cell] = true
				_min_cell.x = mini(_min_cell.x, cell.x)
				_min_cell.y = mini(_min_cell.y, cell.y)
				_max_cell.x = maxi(_max_cell.x, cell.x)
				_max_cell.y = maxi(_max_cell.y, cell.y)
	if _floor_cells.is_empty():
		# An intentionally empty LDtk canvas remains a usable authoring preview.
		_floor_bounds = Rect2(Vector2.ZERO, Vector2(width, height))
	else:
		_floor_bounds = Rect2(Vector2(_min_cell * TILE_SIZE), Vector2((_max_cell - _min_cell + Vector2i.ONE) * TILE_SIZE))
	y_sort_enabled = true
	var geometry: RefCounted = MAP_GEOMETRY.new()
	geometry.call("build", self, layers, tileset_defs, _floor_cells, _textures)
	var leaves: Node2D = LEAVES.new() as Node2D
	leaves.name = "ForegroundLeaves"
	add_child(leaves)
	leaves.call("build", layers, tileset_defs, _textures)
	var ambient: Node2D = AMBIENT_AREAS.new() as Node2D
	ambient.name = "AmbientAreas"
	add_child(ambient)
	ambient.call("configure", layers, _textures)
	return true


func _make_atlas_source(source_id: int, definitions: Dictionary, tile_set: TileSet) -> TileSetAtlasSource:
	if not definitions.has(source_id):
		return null
	var definition: Dictionary = definitions[source_id]
	var relative_path: String = str(definition.get("relPath", "")).replace("\\", "/")
	if relative_path.is_empty():
		return null
	var texture: Texture2D = _textures.call("get_texture", relative_path) as Texture2D
	if texture == null:
		return null
	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas.texture = texture
	var grid: int = int(definition.get("tileGridSize", TILE_SIZE))
	atlas.texture_region_size = Vector2i(grid, grid)
	tile_set.add_source(atlas, source_id)
	return atlas


func _layer_z_index(layer_name: String) -> int:
	match layer_name:
		"Floor": return -20
		"WallsBack": return -14
		"WallsSides": return -10
		"ObjectsBack": return -5
		"WallsFront": return 3
		"ObjectsFront": return 6
		"Doors": return 8
		_: return -2


func _build_floor_collisions() -> void:
	var walls: StaticBody2D = StaticBody2D.new()
	walls.name = "FloorBoundary"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for cell_variant in _floor_cells.keys():
		var cell: Vector2i = cell_variant
		for direction in directions:
			if _floor_cells.has(cell + direction):
				continue
			if bool(_gameplay.call("is_gap_cell", cell + direction)):
				continue
			var shape: RectangleShape2D = RectangleShape2D.new()
			shape.size = Vector2(16.0, 4.0) if direction.x == 0 else Vector2(4.0, 16.0)
			var collision: CollisionShape2D = CollisionShape2D.new()
			collision.shape = shape
			collision.position = Vector2(cell * TILE_SIZE) + Vector2(8.0, 8.0) + Vector2(direction * 8)
			walls.add_child(collision)


func _add_training_player_and_controls() -> void:
	var training_root: Node = TRAINING_SCENE.instantiate()
	var player: Player = training_root.get_node("Nox") as Player
	player.position = _entrance_spawn()
	player.set_respawn_position(player.position)
	player.movement_speed = 94.3
	player.arena_bounds = _floor_bounds
	player.movement_bounds = _floor_bounds.grow(-4.0)
	player.intro_locked = true
	player.dash_afterimages_enabled = false
	var keep_nodes: Array[String] = ["Nox", "ManifestationProjectiles", "CombatUI", "ManifestationController"]
	for node_name in keep_nodes:
		var node: Node = training_root.get_node_or_null(NodePath(node_name))
		if node == null:
			push_error("Controle de treino ausente: " + node_name)
			continue
		training_root.remove_child(node)
		node.owner = null
		add_child(node)
	training_root.free()
	# The training companion raises Body's Z for a flat arena. Here the body
	# must share the world volumes' depth band to pass behind their bases.
	player.body.z_index = 0
	var gun: Node2D = player.get_node("BoosterShooter") as Node2D
	var companion: Node2D = gun.get("companion") as Node2D
	if companion != null:
		companion.z_index = 1
	var camera: Camera2D = player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.zoom = Vector2(0.95, 0.95)
		camera.limit_left = floori(_floor_bounds.position.x - 32.0)
		camera.limit_top = floori(_floor_bounds.position.y - 32.0)
		camera.limit_right = ceili(_floor_bounds.end.x + 32.0)
		camera.limit_bottom = ceili(_floor_bounds.end.y + 32.0)


func _entrance_spawn() -> Vector2:
	if bool(_gameplay.get("has_start")):
		return _gameplay.get("start_position") as Vector2
	if _floor_cells.is_empty():
		return _floor_bounds.get_center()
	var entrance_x: int = _min_cell.x + 2
	var low_y: int = 2147483647
	var high_y: int = -2147483647
	for cell_variant in _floor_cells.keys():
		var cell: Vector2i = cell_variant
		if cell.x == entrance_x:
			low_y = mini(low_y, cell.y)
			high_y = maxi(high_y, cell.y)
	if high_y < low_y:
		return _floor_bounds.position + Vector2(40.0, 40.0)
	return Vector2((float(entrance_x) + 0.5) * TILE_SIZE, (float(low_y + high_y + 1) * 0.5) * TILE_SIZE)


func _fade_in() -> void:
	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.name = "EntryFade"
	overlay.layer = 100
	var cover: ColorRect = ColorRect.new()
	cover.name = "Cover"
	cover.color = Color.BLACK
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cover)
	add_child(overlay)
	var fade: Tween = create_tween()
	fade.tween_property(cover, "modulate:a", 0.0, 0.45)
	fade.tween_callback(func() -> void:
		var player: Player = get_node_or_null("Nox") as Player
		if player != null:
			player.intro_locked = false
		overlay.queue_free()
	)
