extends Node2D

const MAP_PATH: String = "res://monster_booster.ldtk"
const LEVEL_NAME: String = "RoomTemplate_30x16"
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const GAMEPLAY_KIT: Script = preload("res://scripts/combat/player_gameplay_kit.gd")
const TILE_SIZE: int = 16
const MAP_GEOMETRY: Script = preload("res://scripts/dungeon/ldtk_map_geometry.gd")
const LEVEL_COMPOSITION: Script = preload("res://scripts/dungeon/ldtk_level_composition.gd")
const GAMEPLAY: Script = preload("res://scripts/dungeon/ldtk_gameplay.gd")
const TEXTURE_SOURCE: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
const LEAVES: Script = preload("res://scripts/dungeon/ldtk_leaves.gd")
const TREES: Script = preload("res://scripts/dungeon/ldtk_trees.gd")
const VEGETATION: Script = preload("res://scripts/dungeon/ldtk_vegetation.gd")
const BRIDGES: Script = preload("res://scripts/dungeon/ldtk_bridges.gd")
const TREE_SHADOWS: Script = preload("res://scripts/visual/tree_shadows.gd")
const BORDERS: Script = preload("res://scripts/dungeon/ldtk_borders.gd")
const AMBIENT_AREAS: Script = preload("res://scripts/dungeon/ldtk_ambient_areas.gd")
const WATER_AREAS: Script = preload("res://scripts/dungeon/ldtk_water_areas.gd")
const WATER_SURFACE: Script = preload("res://scripts/visual/water_surface.gd")
const WATER_TERRAIN: Script = preload("res://scripts/dungeon/ldtk_water_terrain.gd")
const TERRAIN_WATER_MASK: Script = preload("res://scripts/dungeon/ldtk_terrain_water_mask.gd")
const RIVER_CONTOUR: Script = preload("res://scripts/dungeon/ldtk_river_contour.gd")
const WATER_BACKGROUND: Script = preload("res://scripts/visual/water_background.gd")
const WATER_SHORES: Script = preload("res://scripts/dungeon/ldtk_water_shores.gd")
const ROOM_LIGHTING: Script = preload("res://scripts/visual/room_lighting.gd")
const WARPS: Script = preload("res://scripts/dungeon/ldtk_warps.gd")
const WARP_TRANSITION: Script = preload("res://scripts/visual/warp_transition.gd")
const SPIRIT_HORDES: Script = preload("res://scripts/dungeon/ldtk_spirit_hordes.gd")
const FLYING_EYE_ZONES: Script = preload("res://scripts/dungeon/flying_eye_zones.gd")
const ENEMY_REMAINS: Script = preload("res://scripts/visual/enemy_remains.gd")
const HORDE_PEDESTALS: Script = preload("res://scripts/dungeon/ldtk_horde_pedestals.gd")
const ELEVATION: Script = preload("res://scripts/dungeon/ldtk_elevation.gd")
const PLAYER_DEFEAT: Script = preload("res://scripts/visual/player_defeat.gd")
const TERRAIN_CLOUDS: Script = preload("res://scripts/visual/terrain_cloud_shadows.gd")
const SOIL_MATERIAL: ShaderMaterial = preload("res://resources/visual/terrain/open_world_soil.tres")
const BACKGROUND_COLOR: Color = Color("#25131a")

var _floor_cells: Dictionary = {}
var _floor_bounds: Rect2 = Rect2()
var _min_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _max_cell: Vector2i = Vector2i(-2147483647, -2147483647)
signal entry_finished
signal warp_travel_failed(reason: String)
var entry_complete: bool = false
var last_warp_error: String = ""
var entry_player_state: Dictionary = {}
@export var arrival_warp_id: String = ""
@export var warp_entry_cutscene_enabled: bool = true
@export_range(0.2,3.0,0.05) var warp_arrival_duration: float = 0.6
@export_range(0.2,3.0,0.05) var warp_departure_duration: float = 0.4
@export var map_path: String = MAP_PATH
@export var level_name: String = LEVEL_NAME
@export var automatic_water: bool = true
@export var water_profile: WaterProfile = preload("res://resources/visual/water/sea.tres")
@export var shore_foam_enabled: bool = true
@export var river_contour_enabled: bool = false
@export_range(0.25, 1.5, 0.05) var river_edge_softness_px: float = 1.0
@export var lighting_profile: Resource
@export var lighting_setups: Resource
@export var terrain_material: ShaderMaterial
@export_range(0.5, 3.0, 0.05) var border_brightness: float = 1.0
var _camera: Camera2D = null
var _gameplay: Node2D
var _textures: RefCounted = TEXTURE_SOURCE.new()
var _texture_refresh_remaining: float = 0.0
var _warps: Node2D = null
var _arrival_gate: Node2D = null
var _warp_effect: CanvasLayer = null
var _travel_busy: bool = false
var _pending_route: Dictionary = {}
var _level_layers: Array = []
var _elevation: Node2D = null
var _completion_skip_requested: bool = false
var _defeat: CanvasLayer = null
var _river_contour: Node2D = null


func _process(delta: float) -> void:
	if _completion_skip_requested and entry_complete and not _travel_busy:
		_completion_skip_requested = false
		var player: Player = get_node_or_null("Nox") as Player
		if player != null and not player.dead:
			for encounter: Node2D in get_node("SpiritHordes").get("encounters"):
				encounter.call("skip_to_completion")
	_texture_refresh_remaining -= delta
	if _texture_refresh_remaining <= 0.0:
		_texture_refresh_remaining = 0.3
		_textures.call("refresh")


func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if level_name != "Room_1" or key == null or not key.pressed or key.echo or _travel_busy:
		return
	if key.physical_keycode != KEY_TAB and key.keycode != KEY_TAB:
		return
	_completion_skip_requested = true
	get_viewport().set_input_as_handled()


func _ready() -> void:
	if not _build_ldtk_level():
		push_error("Nao foi possivel carregar a arena LDtk: " + map_path)
		return
	_build_floor_collisions()
	_add_player_and_controls()
	get_node("Vegetation").call("bind_player", get_node("Nox"))
	_defeat = PLAYER_DEFEAT.new() as CanvasLayer
	_defeat.name = "PlayerDefeat"
	add_child(_defeat)
	_defeat.call("bind_player", get_node("Nox"), self)
	_capture_arrival_checkpoint()
	var player_hud: CanvasLayer = get_node_or_null("PlayerHUD") as CanvasLayer
	if player_hud != null:
		player_hud.call("bind_player", get_node("Nox"))
	var remains: Node2D = ENEMY_REMAINS.new() as Node2D
	remains.name = "EnemyRemains"
	add_child(remains)
	remains.call("configure", is_ground_surface_point, get_node("Nox"))
	var hordes: Node2D = SPIRIT_HORDES.new() as Node2D
	hordes.name = "SpiritHordes"
	add_child(hordes)
	var allowed_cells: Dictionary = _combat_allowed_cells()
	hordes.call("build", _level_layers, get_node("Nox"), _gameplay, is_sword_ground_point, remains, Callable(_elevation, "height_at"), allowed_cells)
	var pedestals: Node2D = HORDE_PEDESTALS.new() as Node2D
	pedestals.name = "HordePedestals"
	add_child(pedestals)
	pedestals.call("build", _level_layers, _textures, get_node("Nox"), hordes.get("encounters"), Callable(_elevation, "height_at"))
	var ambient_enemies: Node2D = FLYING_EYE_ZONES.new() as Node2D
	ambient_enemies.name = "FlyingEyeZones"
	add_child(ambient_enemies)
	ambient_enemies.call("configure", _level_layers, get_node("Nox"), _gameplay, allowed_cells, is_ground_surface_point, Callable(_elevation, "height_at"), hordes.get("encounters"))
	if lighting_profile != null:
		var lighting: CanvasLayer = ROOM_LIGHTING.new() as CanvasLayer
		lighting.name = "RoomLighting"
		lighting.set("profile", lighting_profile)
		lighting.set("setups", lighting_setups)
		lighting.set("subject", get_node("Nox"))
		add_child(lighting)
	if _arrival_gate != null and warp_entry_cutscene_enabled:
		_start_warp_effect(true)
	else:
		_fade_in()


func _build_ldtk_level() -> bool:
	var map_file: FileAccess = FileAccess.open(map_path, FileAccess.READ)
	if map_file == null:
		return false
	var parsed: Variant = JSON.parse_string(map_file.get_as_text())
	if not parsed is Dictionary:
		return false
	var map_data: Dictionary = parsed
	var composition: Dictionary = LEVEL_COMPOSITION.compose(map_data, level_name)
	if not bool(composition.get("ok", false)):
		push_error(str(composition.get("error", "Composicao LDtk invalida.")))
		return false
	var level: Dictionary = composition.primary as Dictionary
	var layers: Array = composition.layers as Array
	var has_solid_base: bool = false
	for layer: Dictionary in layers:
		if str(layer.get("__identifier", "")) == "GroundBase" and bool(layer.get("visible", true)):
			has_solid_base = true
	set_meta(&"composed_levels", composition.source_levels)
	_level_layers = layers
	_elevation = ELEVATION.new() as Node2D
	_elevation.name = "TerrainElevation"
	add_child(_elevation)
	_elevation.call("configure", layers)
	_gameplay = GAMEPLAY.new() as Node2D
	_gameplay.name = "Gameplay"
	add_child(_gameplay)
	_gameplay.call("configure", layers)
	var tileset_defs: Dictionary = {}
	var definitions: Dictionary = map_data.get("defs", {})
	for definition_variant in definitions.get("tilesets", []):
		var definition: Dictionary = (definition_variant as Dictionary).duplicate()
		var relative: String = str(definition.get("relPath","")).replace("\\","/")
		if not relative.is_empty() and not relative.begins_with("res://"):
			var local_source: String = map_path.get_base_dir().path_join(relative).simplify_path()
			if FileAccess.file_exists(local_source) or ResourceLoader.exists(local_source):
				definition["relPath"] = local_source
		tileset_defs[int(definition.get("uid", -1))] = definition
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var atlas_sources: Dictionary = {}
	var backdrop: Polygon2D = Polygon2D.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(str(level.get("__bgColor", "#533048"))) if has_solid_base else BACKGROUND_COLOR
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
	var ground_surfaces: Array[TileMapLayer] = []
	var rim_replacements: Dictionary = TERRAIN_WATER_MASK.replacement_cells(layers)
	var ground_profile: ShaderMaterial = terrain_material
	if has_solid_base and ground_profile == null: ground_profile = SOIL_MATERIAL
	for layer_variant in layers:
		var layer: Dictionary = layer_variant
		if not bool(layer.get("visible", true)):
			continue
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
		if BRIDGES.is_bridge_decoration(layer_name):
			continue
		var is_floor: bool = layer_name == "Floor" or layer_name.begins_with("Floor_")
		if layer_name.begins_with("Walls") or layer_name.begins_with("Objects") or layer_name in ["Borders", "Barriers"]:
			continue
		var source_id: int = int(layer.get("__tilesetDefUid", -1))
		# A copied soil atlas also gives the LDtk room template the same ground effect.
		if ground_profile == null and str((tileset_defs.get(source_id, {}) as Dictionary).get("relPath", "")).ends_with("/monstershift/texturized_floor_atlas.png"):
			ground_profile = SOIL_MATERIAL
		if LEAVES.is_leaves_source(tileset_defs.get(source_id, {})) or TREES.is_tree_source(tileset_defs.get(source_id, {})):
			continue
		if VEGETATION.is_vegetation_source(tileset_defs.get(source_id, {})):
			continue
		if not atlas_sources.has(source_id):
			var source: TileSetAtlasSource = _make_atlas_source(source_id, tileset_defs, tile_set)
			if source == null:
				push_error("Tileset LDtk ausente na camada " + layer_name)
				return false
			atlas_sources[source_id] = source
		var atlas: TileSetAtlasSource = atlas_sources[source_id]
		var layer_nodes: Dictionary = {}
		var stack_counts: Dictionary = {}
		for tile_variant in tiles:
			var tile: Dictionary = tile_variant
			var pixel: Array = tile.get("px", [])
			var source_pixel: Array = tile.get("src", [])
			if pixel.size() < 2 or source_pixel.size() < 2:
				continue
			var cell: Vector2i = Vector2i(floori(float(pixel[0]) / TILE_SIZE), floori(float(pixel[1]) / TILE_SIZE))
			if is_floor and bool(_gameplay.call("is_gap_cell", cell)):
				continue
			if is_floor:
				_floor_cells[cell] = true
				_min_cell.x = mini(_min_cell.x, cell.x)
				_min_cell.y = mini(_min_cell.y, cell.y)
				_max_cell.x = maxi(_max_cell.x, cell.x)
				_max_cell.y = maxi(_max_cell.y, cell.y)
				# The contour's opaque interior replaces the square Floor artwork.
				# Keep its logical support, but let transparent edge pixels reveal water.
				if rim_replacements.has(cell):
					continue
			var atlas_cell: Vector2i = Vector2i(floori(float(source_pixel[0]) / TILE_SIZE), floori(float(source_pixel[1]) / TILE_SIZE))
			if not atlas.has_tile(atlas_cell):
				atlas.create_tile(atlas_cell)
			var depth: int = int(stack_counts.get(cell, 0))
			stack_counts[cell] = depth + 1
			var raised: int = roundi(float(_elevation.call("height_at", to_global(Vector2(cell * TILE_SIZE) + Vector2.ONE * 8.0)))) if is_floor or layer_name == "TerrainStairs" else 0
			var render_key: String = "%d_%d" % [depth, raised]
			if not layer_nodes.has(render_key):
				var tile_layer: TileMapLayer = TileMapLayer.new()
				tile_layer.name = layer_name + "_" + str(layer_nodes.size())
				tile_layer.tile_set = tile_set
				tile_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				var art_path: String = str((tileset_defs.get(source_id, {}) as Dictionary).get("relPath", ""))
				var palette: int = 4 if art_path.ends_with("/ground_base.png") else 1 if art_path.ends_with("/grass_tileset.png") or art_path.ends_with("/grass_border_tileset.png") else 2 if art_path.ends_with("/path_tileset.png") else 0
				if art_path.ends_with("/cliff_tileset.png") or art_path.ends_with("/water_bank_tileset_64.png") or art_path.ends_with("/water_bank_tileset_64_mapped.png"): palette = 5
				tile_layer.set_meta(&"asset_palette", palette)
				tile_layer.z_index = _layer_z_index(layer_name) + depth
				tile_layer.position = Vector2(float(layer.get("pxOffsetX", 0)), float(layer.get("pxOffsetY", 0)) - raised)
				map_root.add_child(tile_layer)
				if is_floor or layer_name in ["TerrainStairs", "TerrainFaces", "TerrainCliffRim", "WaterBanks", "GroundBase"]:
					ground_surfaces.append(tile_layer)
				layer_nodes[render_key] = tile_layer
			var flip_flags: int = 0
			var ld_flip: int = int(tile.get("f", 0))
			if (ld_flip & 1) != 0:
				flip_flags |= TileSetAtlasSource.TRANSFORM_FLIP_H
			if (ld_flip & 2) != 0:
				flip_flags |= TileSetAtlasSource.TRANSFORM_FLIP_V
			(layer_nodes[render_key] as TileMapLayer).set_cell(cell, source_id, atlas_cell, flip_flags)
	if ground_profile != null and not ground_surfaces.is_empty():
		var cloud_shadows: Node = TERRAIN_CLOUDS.new()
		cloud_shadows.name = "TerrainCloudShadows"
		add_child(cloud_shadows)
		cloud_shadows.call("configure", ground_profile, ground_surfaces)
		if has_solid_base:
			# Continue the same cloud shapes behind the trees outside the level;
			# the solid background must not cut them off at a straight map edge.
			backdrop.material = (cloud_shadows.get("palette_materials") as Dictionary).get(4) as ShaderMaterial
	_add_pedestal_support(layers)
	if river_contour_enabled and not automatic_water:
		_river_contour = RIVER_CONTOUR.new() as Node2D
		_river_contour.name = "RiverContour"
		add_child(_river_contour)
		var river_areas: RefCounted = WATER_AREAS.new()
		var river_descriptions: Array = river_areas.call("descriptions_from_layers", layers) as Array
		if not bool(_river_contour.call("configure", layers, river_descriptions, river_edge_softness_px)):
			push_error("RiverContour: " + str(_river_contour.get("diagnostics")))
		else:
			_river_contour.call("bind_ground", ground_surfaces, get_node_or_null("TerrainCloudShadows"), _floor_cells, _textures.call("get_texture", "res://assets/tiles/floor/ground_base.png") as Texture2D)
	if _floor_cells.is_empty():
		# An intentionally empty LDtk canvas remains a usable authoring preview.
		_floor_bounds = Rect2(Vector2.ZERO, Vector2(width, height))
	else:
		_floor_bounds = Rect2(Vector2(_min_cell * TILE_SIZE), Vector2((_max_cell - _min_cell + Vector2i.ONE) * TILE_SIZE))
	y_sort_enabled = true
	var geometry: RefCounted = MAP_GEOMETRY.new()
	geometry.call("build", self, layers, tileset_defs, _floor_cells, _textures, Callable(_elevation, "height_at"))
	var borders: Node2D = BORDERS.new() as Node2D
	borders.name = "Borders"
	borders.set("brightness", border_brightness)
	add_child(borders)
	borders.call("build", layers, tileset_defs, _textures)
	var barriers: Node2D = BORDERS.new() as Node2D
	barriers.name = "Barriers"
	barriers.set("layer_name", "Barriers")
	add_child(barriers)
	barriers.call("build", layers, tileset_defs, _textures)
	var leaves: Node2D = LEAVES.new() as Node2D
	leaves.name = "ForegroundLeaves"
	add_child(leaves)
	leaves.call("build", layers, tileset_defs, _textures)
	var trees: Node2D = TREES.new() as Node2D
	trees.name = "Trees"
	add_child(trees)
	trees.call("build", layers, tileset_defs, _textures, Callable(_elevation, "height_at"))
	var vegetation: Node2D = VEGETATION.new() as Node2D
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.call("build", layers, tileset_defs, _textures, Callable(_elevation, "height_at"))
	if has_solid_base:
		var tree_shadows: Node2D = TREE_SHADOWS.new() as Node2D
		tree_shadows.name = "TreeShadows"
		add_child(tree_shadows)
		tree_shadows.call("configure", trees.call("shadow_descriptions"))
	var ambient: Node2D = AMBIENT_AREAS.new() as Node2D
	ambient.name = "AmbientAreas"
	add_child(ambient)
	ambient.call("configure", layers, _textures)
	if automatic_water:
		var terrain: RefCounted = WATER_TERRAIN.new()
		var background: Node2D = WATER_BACKGROUND.new() as Node2D
		background.name = "Water"
		background.set("profile", water_profile)
		background.set("foam_enabled", shore_foam_enabled)
		add_child(background)
		var solid_cells: Dictionary = terrain.call(&"opaque_cells", layers, tileset_defs, _textures, _floor_cells)
		var shores: RefCounted = WATER_SHORES.new()
		background.call(&"configure", solid_cells, terrain.get("shore_styles"), shores.call(&"descriptions_from_layers", layers))
	else:
		var water_adapter: RefCounted = WATER_AREAS.new()
		var descriptions: Array = water_adapter.call(&"descriptions_from_layers", layers)
		for description: Dictionary in descriptions:
			if bool(description.get("clip_to_terrain", false)) and str(description.get("mask_id", "Rectangle")) == "Rectangle":
				description["mask_texture"] = TERRAIN_WATER_MASK.build(description.rect as Rect2, _floor_cells, layers, tileset_defs, _textures, _local_terrain_height)
		if not descriptions.is_empty():
			var water: WaterSurface = WATER_SURFACE.new() as WaterSurface
			water.name = "Water"
			if water_profile != null:
				water.profiles = water.profiles.duplicate()
				for index: int in range(water.profiles.size()):
					if water.profiles[index].preset_id == water_profile.preset_id:
						water.profiles[index] = water_profile
			add_child(water)
			water.configure(descriptions, _textures)
			if _river_contour != null:
				_river_contour.call("bind_water", water, shore_foam_enabled)
	var bridges: Node2D = BRIDGES.new() as Node2D
	bridges.name = "BridgeGeometry"
	add_child(bridges)
	var clouds: Node = get_node_or_null("TerrainCloudShadows")
	var bridge_material: ShaderMaterial = clouds.get("soil_material") as ShaderMaterial if clouds != null else null
	bridges.call("build", layers, tileset_defs, _textures, get_node_or_null("Water"), is_ground_surface_point, bridge_material)
	_warps = WARPS.new() as Node2D
	_warps.name = "Warps"
	add_child(_warps)
	_warps.call("build",layers,_textures)
	_arrival_gate = _warps.call("entrance",arrival_warp_id) as Node2D
	_warps.connect("travel_requested",func(gate: Node2D) -> void: call_deferred("_begin_warp_travel",gate))
	return true


func _add_pedestal_support(layers: Array) -> void:
	# Platforms supply walkable support even when the author places them over absent Floor.
	# Preserve the map paint and derive FloorBoundary from the combined surface.
	for region: Rect2 in HORDE_PEDESTALS.support_regions(layers):
		var first: Vector2i = Vector2i((region.position / TILE_SIZE).floor())
		var ending: Vector2i = Vector2i((region.end / TILE_SIZE).ceil())
		for y: int in range(first.y, ending.y):
			for x: int in range(first.x, ending.x):
				var cell: Vector2i = Vector2i(x, y)
				if not region.has_point(Vector2(cell * TILE_SIZE) + Vector2.ONE * 8.0) or bool(_gameplay.call("is_gap_cell", cell)):
					continue
				_floor_cells[cell] = true
				_min_cell = _min_cell.min(cell)
				_max_cell = _max_cell.max(cell)


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
	var grid: int = int(definition.get("tileGridSize", TILE_SIZE))
	if texture.get_width() % grid != 0 or texture.get_height() % grid != 0:
		var padded: ImageTexture = ImageTexture.new()
		_refresh_padded_atlas(texture, padded, grid)
		texture.changed.connect(_refresh_padded_atlas.bind(texture, padded, grid))
		atlas.texture = padded
	else:
		atlas.texture = texture
	atlas.texture_region_size = Vector2i(grid, grid)
	tile_set.add_source(atlas, source_id)
	return atlas


func _refresh_padded_atlas(source: Texture2D, target: ImageTexture, grid: int) -> void:
	# LDtk allows a final partial cell (e.g. a 124px PNG in a 16px atlas).
	# Godot needs complete cells: preserve the authored pixels and pad only in memory.
	var original: Image = source.get_image()
	if original.is_compressed():
		original.decompress()
	var width: int = ceili(float(original.get_width()) / grid) * grid
	var height: int = ceili(float(original.get_height()) / grid) * grid
	var padded: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	padded.fill(Color.TRANSPARENT)
	padded.blit_rect(original, Rect2i(Vector2i.ZERO, original.get_size()), Vector2i.ZERO)
	target.set_image(padded)


func _layer_z_index(layer_name: String) -> int:
	match layer_name:
		"Floor_Castle": return -19
		"Floor_Grass": return -19
		"Floor_GrassBorders": return -17
		"Floor_StonePaths": return -17
		"Floor_Paths": return -18
		"Floor_Bridges": return -16
		"TerrainFaces": return -17
		"TerrainCliffRim": return -18
		"TerrainStairs": return -15
		"Floor": return -20
		"WaterBanks": return -17
		"GroundBase": return -90
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
			var edge_midpoint: Vector2 = Vector2(cell * TILE_SIZE) + Vector2.ONE * 8.0 + Vector2(direction * 8)
			if _river_contour != null and bool(_river_contour.call("replaces_grid_edge", edge_midpoint)):
				continue
			var shape: Shape2D = _river_contour.call("transition_shape", edge_midpoint, direction) as Shape2D if _river_contour != null else null
			if shape == null:
				var rectangle: RectangleShape2D = RectangleShape2D.new()
				rectangle.size = Vector2(16.0, 4.0) if direction.x == 0 else Vector2(4.0, 16.0)
				shape = rectangle
			var collision: CollisionShape2D = CollisionShape2D.new()
			collision.shape = shape
			collision.position = Vector2(cell * TILE_SIZE) + Vector2(8.0, 8.0) + Vector2(direction * 8)
			walls.add_child(collision)
	if _river_contour != null:
		_river_contour.call("add_collision", walls)


func _add_player_and_controls() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.name = "Nox"
	player.position = _entrance_spawn()
	player.set_respawn_position(player.position)
	player.movement_speed = 94.3
	player.arena_bounds = _floor_bounds
	player.movement_bounds = _floor_bounds.grow(-4.0)
	player.intro_locked = true
	player.dash_afterimages_enabled = false
	add_child(player)
	# Keep the body in the world's depth band to pass behind props' bases.
	player.body.z_index = 0
	var kit: Node2D = GAMEPLAY_KIT.new() as Node2D
	kit.name = "GameplayKit"
	kit.set("world_bounds", Rect2(to_global(_floor_bounds.position), _floor_bounds.size * global_scale))
	kit.set("gameplay", _gameplay)
	kit.set("procedural_weapons_enabled", level_name == "Room_2")
	player.add_child(kit)
	# Side-facing weapon shares the actor's depth; upward/recoil poses stay behind it.
	# This lets the whole held rig disappear behind a Y-sorted tree, with the body.
	player.get_node("BoosterShooter").set("z_index", -2)
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	_warps.call("bind_actor", player, _gameplay)
	if not entry_player_state.is_empty():
		player.max_health = float(entry_player_state.get("max_health",player.max_health))
		player.health = clampf(float(entry_player_state.get("health",player.health)),0.0,player.max_health)
		player.dash_charges = int(entry_player_state.get("dash_charges",player.dash_charges))
		player.dash_recovery = float(entry_player_state.get("dash_recovery",0.0))
		var shooter: Node = player.get_node("BoosterShooter")
		if entry_player_state.has("card_runtime"):
			shooter.set("card_runtime",entry_player_state.card_runtime)
		shooter.set("cooldown",float(entry_player_state.get("cooldown",0.0)))
		player.health_changed.emit(player.health,player.max_health)


func is_sword_ground_point(world_point: Vector2) -> bool:
	return is_ground_surface_point(world_point)


func _local_terrain_height(point: Vector2) -> float:
	return float(_elevation.call("height_at", to_global(point)))


func _combat_allowed_cells() -> Dictionary:
	var allowed: Dictionary = _floor_cells.duplicate()
	if _river_contour != null:
		_river_contour.call("update_allowed_cells", allowed)
	# GroundBase is presentation only. Respect the authored world barriers,
	# even where terrain extends under the outer forest strip.
	for layer: Dictionary in _level_layers:
		if str(layer.get("__identifier", "")) != "Gameplay": continue
		var width: int = int(layer.get("__cWid", 1))
		var grid: int = int(layer.get("__gridSize", TILE_SIZE))
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		var values: Array = layer.get("intGridCsv", []) as Array
		for index: int in range(values.size()):
			if int(values[index]) not in [1, 2, 3, 6, 7]: continue
			var point: Vector2 = Vector2(index % width, floori(float(index) / width)) * grid + offset
			var first: Vector2i = Vector2i((point / TILE_SIZE).floor())
			var ending: Vector2i = Vector2i(((point + Vector2.ONE * grid) / TILE_SIZE).ceil())
			for y: int in range(first.y, ending.y):
				for x: int in range(first.x, ending.x): allowed.erase(Vector2i(x, y))
	for cell: Vector2i in allowed.keys():
		if bool(_gameplay.call("is_gap_cell", cell)): allowed.erase(cell)
	return allowed


func is_ground_surface_point(world_point: Vector2) -> bool:
	var point: Vector2 = to_local(world_point)
	if bool(_gameplay.call("is_gap_point", point)):
		return false
	if _river_contour != null:
		var river_support: int = int(_river_contour.call("ground_override", point))
		if river_support >= 0: return river_support == 1
	if _floor_cells.is_empty():
		return _floor_bounds.has_point(point)
	var cell: Vector2i = Vector2i((point / TILE_SIZE).floor())
	return _floor_cells.has(cell)


func _entrance_spawn() -> Vector2:
	if _arrival_gate != null:
		return _arrival_gate.call("spawn_position") as Vector2
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
		_finish_entry()
		overlay.queue_free()
	)


func _finish_entry() -> void:
	var player: Player = get_node_or_null("Nox") as Player
	if player != null:
		player.intro_locked = false
	entry_complete = true
	_travel_busy = false
	entry_finished.emit()


func _start_warp_effect(arriving: bool) -> void:
	if _warp_effect == null:
		_warp_effect = WARP_TRANSITION.new() as CanvasLayer
		_warp_effect.name = "WarpTransition"
		_warp_effect.set("arrival_duration",warp_arrival_duration)
		_warp_effect.set("departure_duration",warp_departure_duration)
		add_child(_warp_effect)
		_warp_effect.connect("finished",_on_warp_effect_finished)
	_warp_effect.call("play",arriving,get_node("Nox"))


func _begin_warp_travel(gate: Node2D) -> void:
	var player: Player = get_node_or_null("Nox") as Player
	if _travel_busy or not is_instance_valid(gate) or player == null or player.intro_locked or player.dead:
		return
	if not bool(gate.call("can_travel")):
		return
	_pending_route = WARPS.resolve(map_path,gate.get("data"))
	if not bool(_pending_route.get("ok",false)):
		last_warp_error = str(_pending_route.get("error","Destino indisponivel."))
		warp_travel_failed.emit(last_warp_error)
		return
	_pending_route["restart_game"] = bool((gate.get("data") as Dictionary).get("RestartGame", false))
	_travel_busy = true
	entry_complete = false
	_start_warp_effect(false)


func _on_warp_effect_finished(arriving: bool) -> void:
	if arriving:
		_finish_entry()
		return
	var player: Player = get_node("Nox") as Player
	if _pending_route.has("scene_path"):
		_travel_to_scene(player, str(_pending_route.scene_path))
		return
	if bool(_pending_route.get("restart_game", false)):
		_restart_from_beginning()
		return
	if str(_pending_route.map_path) == map_path and str(_pending_route.level_name) == level_name:
		arrival_warp_id = str(_pending_route.arrival_warp)
		player.position = _pending_route.spawn
		player.set_respawn_position(player.position)
		player.snap_floor_height()
		player.reset_physics_interpolation()
		for gate: Node2D in _warps.get("gates"):
			gate.set("_armed",false)
		_camera.reset_smoothing()
		_camera.force_update_scroll()
		_capture_arrival_checkpoint()
		_start_warp_effect(true)
		return
	var packed: PackedScene = load("res://scenes/dungeon/ldtk_arena.tscn") as PackedScene
	var next_room: Node2D = packed.instantiate() as Node2D
	next_room.set("map_path",_pending_route.map_path)
	next_room.set("level_name",_pending_route.level_name)
	next_room.set("arrival_warp_id",_pending_route.arrival_warp)
	var shooter: Node = player.get_node("BoosterShooter")
	next_room.set("entry_player_state",{"health":player.health,"max_health":player.max_health,
		"dash_charges":player.dash_charges,"dash_recovery":player.dash_recovery,
		"card_runtime":shooter.get("card_runtime"),"cooldown":shooter.get("cooldown")})
	get_parent().add_child(next_room)
	if not next_room.has_node("Nox") or next_room.get("_arrival_gate") == null:
		next_room.queue_free()
		last_warp_error = "Destino mudou durante o carregamento. Viagem cancelada."
		warp_travel_failed.emit(last_warp_error)
		_camera.make_current()
		_start_warp_effect(true)
		return
	if get_tree().current_scene == self:
		get_tree().current_scene = next_room
	queue_free()


func _capture_arrival_checkpoint() -> void:
	_defeat.call("capture_checkpoint", {"map_path": map_path, "level_name": level_name,
		"arrival_warp_id": arrival_warp_id})


func _travel_to_scene(player: Player, scene_path: String) -> void:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		last_warp_error = "Cena de destino indisponivel. Viagem cancelada."
		warp_travel_failed.emit(last_warp_error)
		_start_warp_effect(true)
		return
	var next_scene: Node = packed.instantiate()
	var shooter: Node = player.get_node("BoosterShooter")
	# Authored destination scenes opt into the same state contract as LDtk rooms.
	if "entry_player_state" in next_scene:
		next_scene.set("entry_player_state", {"health": player.health, "max_health": player.max_health,
			"dash_charges": player.dash_charges, "dash_recovery": player.dash_recovery,
			"card_runtime": shooter.get("card_runtime"), "cooldown": shooter.get("cooldown")})
	get_parent().add_child(next_scene)
	if get_tree().current_scene == self:
		get_tree().current_scene = next_scene
	queue_free()


func _restart_from_beginning() -> void:
	# Recreate the actual main scene: no health, cards, conditions or timers survive.
	var main_path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var packed: PackedScene = load(main_path) as PackedScene
	if packed == null:
		last_warp_error = "Cena inicial indisponivel."
		warp_travel_failed.emit(last_warp_error)
		_start_warp_effect(true)
		return
	var beginning: Node = packed.instantiate()
	get_parent().add_child(beginning)
	if get_tree().current_scene == self:
		get_tree().current_scene = beginning
	queue_free()
