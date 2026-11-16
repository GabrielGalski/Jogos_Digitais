extends RefCounted
## Native LDtk tile layers, using the project's direct-PNG texture provider.
const TEXTURES: Script = preload("res://scripts/dungeon/ldtk_texture_source.gd")
var textures: RefCounted = TEXTURES.new()


func build(parent: Node2D, layers: Array, definitions: Dictionary, origin: Vector2) -> void:
	for layer: Dictionary in layers:
		if layer.get("__type") != "Tiles" or not bool(layer.get("visible",true)): continue
		var tiles: Array = (layer.get("autoLayerTiles",[]) as Array).duplicate()
		tiles.append_array(layer.get("gridTiles",[]) as Array)
		if tiles.is_empty(): continue
		var source: Dictionary = definitions.get(int(layer.get("__tilesetDefUid",-1)),{}) as Dictionary
		var texture: Texture2D = textures.call("get_texture",str(source.get("relPath",""))) as Texture2D
		if texture == null:
			push_error("Elemental LDtk: missing tileset " + str(source.get("relPath","")))
			continue
		var grid: int = int(layer.__gridSize)
		var tile_set: TileSet = TileSet.new()
		tile_set.tile_size = Vector2i(grid,grid)
		var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
		atlas.texture = texture
		atlas.texture_region_size = Vector2i(grid,grid)
		var padding: int = int(source.get("padding",0))
		var spacing: int = int(source.get("spacing",0))
		atlas.margins = Vector2i.ONE*padding
		atlas.separation = Vector2i.ONE*spacing
		tile_set.add_source(atlas,0)
		var render_layers: Array[TileMapLayer] = []
		var stack: Dictionary[Vector2i,int] = {}
		for tile: Dictionary in tiles:
			var cell: Vector2i = Vector2i(floori(float(tile.px[0])/grid),floori(float(tile.px[1])/grid))
			var source_cell: Vector2i = Vector2i(floori(float(int(tile.src[0])-padding)/(grid+spacing)),floori(float(int(tile.src[1])-padding)/(grid+spacing)))
			if not atlas.has_tile(source_cell): atlas.create_tile(source_cell)
			var depth: int = stack.get(cell,0)
			stack[cell] = depth+1
			while render_layers.size() <= depth:
				var node: TileMapLayer = TileMapLayer.new()
				node.name = str(layer.__identifier)+"_"+str(render_layers.size())
				node.tile_set = tile_set
				node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				# These floor contours move by fractional screen pixels at the arena zoom.
				# Filter their padded atlas cells locally so diagonal cuts don't shimmer.
				if str(layer.__identifier) in ["Floor_Elemental", "PlatformUnderside", "TerrainCliffRim"]:
					node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				node.position = origin+Vector2(float(layer.get("__pxTotalOffsetX",0)),float(layer.get("__pxTotalOffsetY",0)))
				node.z_index = _depth(str(layer.__identifier))+render_layers.size()
				node.modulate.a = float(layer.get("__opacity",1.0))
				node.set_meta(&"ldtk_tileset",str(source.relPath))
				parent.add_child(node)
				render_layers.append(node)
			var flags: int = 0
			var flip: int = int(tile.get("f",0))
			if flip&1: flags |= TileSetAtlasSource.TRANSFORM_FLIP_H
			if flip&2: flags |= TileSetAtlasSource.TRANSFORM_FLIP_V
			render_layers[depth].set_cell(cell,0,source_cell,flags)


func _depth(layer_name: String) -> int:
	if layer_name == "TerrainCliffRim": return -19
	if layer_name.begins_with("Floor"): return -20
	if layer_name == "WallsFront": return -12
	if layer_name == "WallsSides": return -13
	if layer_name == "WallsBack": return -14
	return -21
