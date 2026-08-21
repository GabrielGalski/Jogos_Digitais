extends Node3D

const FLOOR_TEXTURE: Texture2D = preload("res://sprites/Sprite_floor.png")
const WALL_TEXTURE: Texture2D = preload("res://sprites/Sprite_wall.png")

const GRID_WIDTH := 32
const GRID_DEPTH := 32
const HALF_WIDTH := GRID_WIDTH / 2
const HALF_DEPTH := GRID_DEPTH / 2
const TILE_SIZE := 1.0
const FLOOR_THICKNESS := 0.25
const WALL_HEIGHT := 4
const CEILING_HEIGHT := 4.0


func _ready() -> void:
	var floor_material := _create_material(FLOOR_TEXTURE, 0.16)
	var wall_material := _create_material(WALL_TEXTURE, 0.12)
	_create_floor_and_ceiling(floor_material)
	_create_walls(wall_material)
	_create_collision_geometry()


func _create_material(texture: Texture2D, emission_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.92
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_texture = texture
	material.emission_energy_multiplier = emission_strength
	return material


func _create_floor_and_ceiling(material: Material) -> void:
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(TILE_SIZE, FLOOR_THICKNESS, TILE_SIZE)
	tile_mesh.material = material

	var floor_transforms: Array[Transform3D] = []
	var ceiling_transforms: Array[Transform3D] = []
	for x in range(-HALF_WIDTH, HALF_WIDTH):
		for z in range(-HALF_DEPTH, HALF_DEPTH):
			var tile_position := Vector3(x + 0.5, -FLOOR_THICKNESS * 0.5, z + 0.5)
			floor_transforms.append(Transform3D(Basis.IDENTITY, tile_position))
			var ceiling_position := Vector3(x + 0.5, CEILING_HEIGHT + FLOOR_THICKNESS * 0.5, z + 0.5)
			ceiling_transforms.append(Transform3D(Basis.IDENTITY, ceiling_position))

	_create_multimesh("FloorBlocks", tile_mesh, floor_transforms)
	_create_multimesh("CeilingBlocks", tile_mesh, ceiling_transforms)


func _create_walls(material: Material) -> void:
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3.ONE
	cube_mesh.material = material

	var wall_transforms: Array[Transform3D] = []
	for cell in _get_wall_cells():
		for level in WALL_HEIGHT:
			var block_position := Vector3(cell.x + 0.5, level + 0.5, cell.y + 0.5)
			wall_transforms.append(Transform3D(Basis.IDENTITY, block_position))

	_create_multimesh("WallBlocks", cube_mesh, wall_transforms)


func _create_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	add_child(instance)


func _create_collision_geometry() -> void:
	var geometry := StaticBody3D.new()
	geometry.name = "DungeonCollision"
	add_child(geometry)

	_add_box_collision(
		geometry,
		"FloorCollision",
		Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0),
		Vector3(GRID_WIDTH, FLOOR_THICKNESS, GRID_DEPTH)
	)
	_add_box_collision(
		geometry,
		"CeilingCollision",
		Vector3(0.0, CEILING_HEIGHT + FLOOR_THICKNESS * 0.5, 0.0),
		Vector3(GRID_WIDTH, FLOOR_THICKNESS, GRID_DEPTH)
	)

	var wall_index := 0
	for cell in _get_wall_cells():
		_add_box_collision(
			geometry,
			"WallCollision_%03d" % wall_index,
			Vector3(cell.x + 0.5, WALL_HEIGHT * 0.5, cell.y + 0.5),
			Vector3(TILE_SIZE, WALL_HEIGHT, TILE_SIZE)
		)
		wall_index += 1


func _add_box_collision(parent: StaticBody3D, node_name: String, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = node_name
	collision.position = center
	collision.shape = shape
	parent.add_child(collision)


func _get_wall_cells() -> Array[Vector2i]:
	var unique_cells: Dictionary = {}

	# Contorno completamente fechado da dungeon.
	for x in range(-HALF_WIDTH, HALF_WIDTH):
		_add_wall_cell(unique_cells, x, -HALF_DEPTH)
		_add_wall_cell(unique_cells, x, HALF_DEPTH - 1)
	for z in range(-HALF_DEPTH + 1, HALF_DEPTH - 1):
		_add_wall_cell(unique_cells, -HALF_WIDTH, z)
		_add_wall_cell(unique_cells, HALF_WIDTH - 1, z)

	# Alas laterais que formam corredores, mantendo o eixo central livre.
	for z in range(-10, -2):
		_add_wall_cell(unique_cells, -9, z)
		_add_wall_cell(unique_cells, 8, z)
	for z in range(3, 11):
		_add_wall_cell(unique_cells, -9, z)
		_add_wall_cell(unique_cells, 8, z)

	for x in range(-14, -9):
		_add_wall_cell(unique_cells, x, -10)
		_add_wall_cell(unique_cells, x, 10)
	for x in range(9, 14):
		_add_wall_cell(unique_cells, x, -10)
		_add_wall_cell(unique_cells, x, 10)

	# Quatro pilares de dois por dois, úteis como cobertura e referência espacial.
	for origin in [Vector2i(-5, -4), Vector2i(3, -4), Vector2i(-5, 3), Vector2i(3, 3)]:
		for offset_x in 2:
			for offset_z in 2:
				_add_wall_cell(unique_cells, origin.x + offset_x, origin.y + offset_z)

	var cells: Array[Vector2i] = []
	for cell in unique_cells:
		cells.append(cell as Vector2i)
	return cells


func _add_wall_cell(cells: Dictionary, x: int, z: int) -> void:
	cells[Vector2i(x, z)] = true
