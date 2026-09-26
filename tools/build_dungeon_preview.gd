extends SceneTree
## Offline authoring only: saves the fixed layout as editable scene nodes.

const FLOOR: TileSet = preload("res://resources/floor_tileset.tres")
const WALL: Texture2D = preload("res://assets/tiles/wall/wall_tileset.png")
var layout: Node2D
var cells: Dictionary[Vector2i, Node2D] = {}
var layers: Dictionary[Node2D, TileMapLayer] = {}

func _initialize() -> void:
	layout = Node2D.new()
	layout.name = "Layout"
	var room_one: Node2D = _section("Room1", Rect2i(0, 0, 320, 192))
	var room_two: Node2D = _section("Room2", Rect2i(288, -416, 480, 320))
	_section("Entrance", Rect2i(-128, 80, 128, 32))
	var corridor: Node2D = _section("Corridor", Rect2i(320, 80, 112, 32))
	_fill(corridor, Rect2i(400, -96, 32, 176))
	_section("ExitDown", Rect2i(656, -96, 32, 112))
	_section("ExitRight", Rect2i(768, -288, 128, 32))
	# Wall helpers remain available below, but this preview has no walls.
	_pillar(room_two, Vector2(464, -304))
	_pillar(room_two, Vector2(624, -208))
	_gate(room_one, "EntranceGate", Rect2(-4, 80, 8, 32), false)
	_gate(room_one, "PassageGate", Rect2(316, 80, 8, 32), true)
	_gate(room_two, "EntranceGate", Rect2(400, -100, 32, 8), false)
	_gate(room_two, "ExitDownGate", Rect2(656, -100, 32, 8), true)
	_gate(room_two, "ExitRightGate", Rect2(764, -288, 8, 32), true)
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(layout) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/dungeon/two_room_layout.tscn") == OK)
	print("FIXED DUNGEON SAVED: ", cells.size(), " floor cells; no walls, gates and pillars")
	layout.free()
	quit()

func _attach(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = layout

func _section(section_name: String, rectangle: Rect2i) -> Node2D:
	var section: Node2D = Node2D.new()
	section.name = section_name
	_attach(layout, section)
	var floor_layer: TileMapLayer = TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = FLOOR
	_attach(section, floor_layer)
	layers[section] = floor_layer
	_fill(section, rectangle)
	return section

func _fill(section: Node2D, rectangle: Rect2i) -> void:
	for y: int in range(floori(rectangle.position.y / 16.0), floori(rectangle.end.y / 16.0)):
		for x: int in range(floori(rectangle.position.x / 16.0), floori(rectangle.end.x / 16.0)):
			var cell: Vector2i = Vector2i(x, y)
			cells[cell] = section
			var decal: bool = posmod(x + y, 2) == 0 and posmod(x * 17 + y * 31, 5) < 2
			layers[section].set_cell(cell, 0, Vector2i(2, 1) if decal else Vector2i(1, 1))

func _build_walls() -> void:
	# Physical footprint is independent of the projected 48px wall face.
	var occupied: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		var section: Node2D = cells[cell]
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
				Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var boundary: Vector2i = cell + direction
			if cells.has(boundary) or occupied.has(boundary):
				continue
			occupied[boundary] = true
			_block(section, "Wall", Rect2(Vector2(boundary) * 16.0, Vector2.ONE * 16.0))
	# Maximal contour runs, not a grid of frontal brick fragments.
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var edge: Dictionary[Vector2i, bool] = {}
		var horizontal: bool = direction.y != 0
		var along: Vector2i = Vector2i.RIGHT if horizontal else Vector2i.DOWN
		for cell: Vector2i in cells:
			if not cells.has(cell + direction):
				edge[cell] = true
		for cell: Vector2i in edge:
			if edge.has(cell - along):
				continue
			var length: int = 1
			while edge.has(cell + along * length):
				length += 1
			if horizontal:
				_front_run(cell, length, direction == Vector2i.UP)
			else:
				_side_run(cell, length, direction == Vector2i.LEFT)

func _piece(parent: Node2D, piece_name: String, source: Rect2, at: Vector2) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = piece_name
	sprite.texture = WALL
	sprite.region_enabled = true
	sprite.region_rect = source
	sprite.centered = false
	sprite.position = at
	sprite.z_index = 1
	_attach(parent, sprite)

func _straight(parent: Node2D, from_x: float, to_x: float, y: float, seed_index: int) -> void:
	var cursor: float = from_x
	var instance_index: int = 0
	# Whole 64px bodies; only the final cut can be 16/32/48px.
	while cursor < to_x:
		var width: float = minf(64.0, to_x - cursor)
		var variant: int = posmod(seed_index + instance_index, 4)
		_piece(parent, "W%02d" % (variant + 1),
			Rect2(192, 16 + variant * 64, width, 48), Vector2(cursor, y))
		cursor += width
		instance_index += 1

func _front_run(cell: Vector2i, length: int, north: bool) -> void:
	var parent: Node2D = cells[cell]
	var left: float = cell.x * 16.0
	var right: float = left + length * 16.0
	var baseline: float = cell.y * 16.0 if north else (cell.y + 1) * 16.0
	var origin_y: float = baseline - 48.0 if north else baseline
	var outer_left: bool = not cells.has(cell + Vector2i.LEFT)
	var outer_right: bool = not cells.has(cell + Vector2i(length, 0))
	# A northern wall rises behind the walking floor. Side terminals retain
	# their own transparency/margins and are never stretched or mirrored.
	if north:
		_piece(parent, "TSE", Rect2(0, 64, 17, 48), Vector2(left - 8, origin_y))
		_piece(parent, "TSD", Rect2(160, 64, 16, 48), Vector2(right - 8, origin_y))
		_straight(parent, left + 8, right - 8, origin_y, cell.x)
		return
	# Southern fronts extend outwards: none of the 48px consumes walkable rows.
	# IE/ID include their lateral junction; the free cap in the inner end is
	# replaced by the straight continuation, preserving the junction at 1:1.
	var start: float = left - 8
	var finish: float = right + 8
	if outer_left and outer_right and length < 7:
		# Dead ends of narrow corridors: full terminals, not overlapping IE/ID.
		_piece(parent, "TIE", Rect2(0, 208, 17, 48), Vector2(left - 8, origin_y))
		_piece(parent, "TID", Rect2(160, 208, 16, 48), Vector2(right - 8, origin_y))
		_straight(parent, left + 8, right - 8, origin_y, cell.x)
		return
	if outer_left:
		_piece(parent, "IE", Rect2(0, 128, 64, 48), Vector2(start, origin_y))
		start += 48.0 if finish - start > 64.0 else 64.0
	if outer_right:
		_piece(parent, "ID", Rect2(112, 128, 64, 48), Vector2(finish - 64, origin_y))
		finish -= 48.0 if finish - start > 64.0 else 64.0
	# Cut at the existing endpoint cells so translucent caps cannot show a
	# rectangular face behind them. Only breaks get QE/QD + optional 1px border.
	if not outer_left:
		_piece(parent, "QD", Rect2(127, 16, 17, 48), Vector2(start - 1, origin_y))
		start += 16.0
	if not outer_right:
		finish -= 16.0
		_piece(parent, "QE", Rect2(48, 16, 16, 48), Vector2(finish, origin_y))
	_straight(parent, start, finish, origin_y, cell.x)

func _side_run(cell: Vector2i, length: int, left_side: bool) -> void:
	var parent: Node2D = cells[cell]
	var x: float = cell.x * 16.0 - 8.0 if left_side else (cell.x + 1) * 16.0 - 8.0
	for index: int in range(length):
		_piece(parent, "LE" if left_side else "LD",
			Rect2(0 if left_side else 160, 176, 16, 16),
			Vector2(x, (cell.y + index) * 16.0))

func _block(parent: Node2D, block_name: String, rectangle: Rect2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = block_name
	body.position = rectangle.get_center()
	# Layer 1 for actors/navigation, layer 5 for dungeon projectile obstruction.
	body.collision_layer = 17
	body.collision_mask = 0
	_attach(parent, body)
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.name = "Collision"
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rectangle.size
	collision.shape = shape
	_attach(body, collision)
	return body

func _gate(parent: Node2D, gate_name: String, rectangle: Rect2, locked: bool) -> void:
	var gate: StaticBody2D = _block(parent, gate_name, rectangle)
	gate.collision_layer = 17 if locked else 0
	# Intentionally no door art: the opening remains an empty passage.

func _pillar(parent: Node2D, at: Vector2) -> void:
	var body: StaticBody2D = _block(parent, "Pillar", Rect2(at - Vector2(10, 7), Vector2(20, 14)))
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Visual"
	sprite.texture = preload("res://assets/tiles/wall/decor/column_square.png")
	sprite.offset.y = -sprite.texture.get_height() * 0.5 + 7.0
	sprite.z_index = 1
	_attach(body, sprite)
