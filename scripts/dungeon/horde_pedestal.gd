extends Node2D
## Authored 64px platform: four-sided relief, E activation and a world-space kill gauge.
const CHARGE: Shader = preload("res://shaders/pedestal_charge.gdshader")
const ACTION_PROMPT: Script = preload("res://scripts/visual/world_action_prompt.gd")
const CIRCULATION: Script = preload("res://scripts/visual/warp_circulation.gd")
const SIZE: int = 64
const KEY_COLOR: Color = Color("#25131a")
const ACTION_OFFSET: Vector2 = Vector2(0, -45)
var data: Dictionary = {}
var player: Player = null
var encounter: Node2D = null
var progress: float = 0.0
var elevation: float = 4.0
var ramp_width: float = 8.0
var _plate: Sprite2D = null
var _image: Image = null
var _material: ShaderMaterial = null
var _charge_mask: ImageTexture = null
var _charge_rect: Rect2i = Rect2i()
var _heights: PackedFloat32Array = PackedFloat32Array()
var _action: Sprite2D = null
var _ring: Node2D = null


func configure(description: Dictionary, texture: Texture2D) -> void:
	data = description
	position = data.position as Vector2
	elevation = maxf(float(data.get("HeightPx", 4)), 0.0)
	ramp_width = maxf(float(data.get("RampWidth", 8)), 1.0)
	z_index = -12
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_plate = Sprite2D.new()
	_plate.name = "Plate"
	_plate.centered = false
	_plate.texture = texture
	_plate.position = Vector2(-32, -32)
	_material = ShaderMaterial.new()
	_material.shader = CHARGE
	_plate.material = _material
	add_child(_plate)
	_ring = CIRCULATION.new() as Node2D
	_ring.name = "WhiteCirculation"
	_ring.z_index = 1
	_ring.visible = false
	add_child(_ring)
	_action = ACTION_PROMPT.new() as Sprite2D
	_action.name = "ActionPrompt"
	_action.call("configure", ACTION_OFFSET)
	add_child(_action)
	_refresh_source()
	if texture != null:
		texture.changed.connect(_refresh_source)


func bind_encounter(subject: Player, horde: Node2D) -> void:
	player = subject
	encounter = horde
	encounter.connect("progress_changed", _on_progress)
	encounter.connect("started", _on_encounter_started)
	_on_progress(int(encounter.get("defeated_count")), int(encounter.get("kill_target")))


func _process(_delta: float) -> void:
	_update_activation_hint()


func _on_encounter_started() -> void:
	_update_activation_hint()


func _update_activation_hint() -> void:
	var available: bool = can_activate()
	if _action != null:
		_action.call("set_available", available)
	if _ring != null:
		_ring.visible = _charge_rect.has_area()


func _on_progress(defeated: int, target: int) -> void:
	progress = clampf(float(defeated) / maxf(float(target), 1.0), 0.0, 1.0)
	_update_charge()


func _update_charge() -> void:
	if _material == null or _image == null:
		return
	# Quantize to the displayed 64px grid, not half-source pixels.
	var scale_y: float = float(SIZE) / float(_image.get_height())
	var native_rows: int = ceili(float(_charge_rect.size.y) * scale_y)
	var visible_rows: int = ceili(progress * float(native_rows))
	var fill_end: float = float(_charge_rect.position.y) + float(visible_rows) / scale_y
	_material.set_shader_parameter("charge_progress", progress)
	_material.set_shader_parameter("filled_y", fill_end / float(_image.get_height()))


func _refresh_source() -> void:
	if _plate.texture == null:
		return
	_image = _plate.texture.get_image()
	if _image == null or _image.is_empty():
		return
	if _image.is_compressed() and _image.decompress() != OK:
		return
	_plate.scale = Vector2(SIZE, SIZE) / Vector2(_image.get_size())
	_map_charge_circle()
	var circle: Rect2 = Rect2(_charge_rect)
	var radii: Vector2 = (circle.size * _plate.scale * 0.5).ceil() + Vector2.ONE
	_ring.call("configure", radii, _plate.position + circle.get_center() * _plate.scale)
	_map_relief()
	_material.set_shader_parameter("charge_mask", _charge_mask)
	_update_charge()


func _map_charge_circle() -> void:
	var matches: Dictionary[Vector2i, bool] = {}
	for y: int in range(_image.get_height()):
		for x: int in range(_image.get_width()):
			var pixel: Color = _image.get_pixel(x, y)
			if pixel.a > 0.99 and pixel.to_html(false) == KEY_COLOR.to_html(false):
				matches[Vector2i(x, y)] = true
	var largest: Array[Vector2i] = []
	while not matches.is_empty():
		var queue: Array[Vector2i] = [matches.keys()[0] as Vector2i]
		matches.erase(queue[0])
		var cursor: int = 0
		while cursor < queue.size():
			var point: Vector2i = queue[cursor]
			cursor += 1
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbour: Vector2i = point + direction
				if matches.erase(neighbour):
					queue.append(neighbour)
		if queue.size() > largest.size():
			largest = queue
	var mask: Image = Image.create(_image.get_width(), _image.get_height(), false, Image.FORMAT_RGBA8)
	mask.fill(Color.TRANSPARENT)
	_charge_rect = Rect2i()
	if not largest.is_empty():
		var low: Vector2i = largest[0]
		var high: Vector2i = largest[0]
		for point: Vector2i in largest:
			mask.set_pixelv(point, Color.WHITE)
			low = low.min(point)
			high = high.max(point)
		_charge_rect = Rect2i(low, high - low + Vector2i.ONE)
	_charge_mask = ImageTexture.create_from_image(mask)


func _map_relief() -> void:
	var inside: PackedByteArray = PackedByteArray()
	inside.resize(SIZE * SIZE)
	var distances: PackedInt32Array = PackedInt32Array()
	distances.resize(SIZE * SIZE)
	distances.fill(-1)
	_heights.resize(SIZE * SIZE)
	_heights.fill(0.0)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var sample_x: int = mini(floori((float(x) + 0.5) * _image.get_width() / SIZE), _image.get_width() - 1)
			var sample_y: int = mini(floori((float(y) + 0.5) * _image.get_height() / SIZE), _image.get_height() - 1)
			inside[y * SIZE + x] = 1 if _image.get_pixel(sample_x, sample_y).a > 0.9 else 0
	var queue: Array[Vector2i] = []
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			if inside[y * SIZE + x] == 0:
				continue
			var point: Vector2i = Vector2i(x, y)
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbour: Vector2i = point + direction
				if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= SIZE or neighbour.y >= SIZE or inside[neighbour.y * SIZE + neighbour.x] == 0:
					distances[y * SIZE + x] = 0
					queue.append(point)
					break
	var cursor: int = 0
	while cursor < queue.size():
		var point: Vector2i = queue[cursor]
		cursor += 1
		var distance: int = distances[point.y * SIZE + point.x]
		_heights[point.y * SIZE + point.x] = elevation * clampf(float(distance) / ramp_width, 0.0, 1.0)
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbour: Vector2i = point + direction
			if neighbour.x >= 0 and neighbour.y >= 0 and neighbour.x < SIZE and neighbour.y < SIZE:
				var index: int = neighbour.y * SIZE + neighbour.x
				if inside[index] != 0 and distances[index] < 0:
					distances[index] = distance + 1
					queue.append(neighbour)


func height_at(world_feet: Vector2) -> float:
	var point: Vector2i = Vector2i((to_local(world_feet) + Vector2(32, 32)).floor())
	if point.x < 0 or point.y < 0 or point.x >= SIZE or point.y >= SIZE or _heights.is_empty():
		return 0.0
	return _heights[point.y * SIZE + point.x]


func can_activate() -> bool:
	return is_instance_valid(player) and is_instance_valid(encounter) and int(encounter.get("phase")) == 0 \
		and bool(encounter.call("can_begin")) \
		and not player.intro_locked and not player.dead and not player.is_dashing() \
		and height_at(player.to_global(Vector2(0, 3))) >= maxf(elevation * 0.9, 0.1) \
		and player.displayed_height >= elevation * 0.8


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or (key.physical_keycode != KEY_E and key.keycode != KEY_E):
		return
	if can_activate():
		get_viewport().set_input_as_handled()
		encounter.call("begin")
