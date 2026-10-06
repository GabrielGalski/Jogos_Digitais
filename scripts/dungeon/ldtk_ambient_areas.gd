extends Node2D
## Visual-only, randomly scheduled LDtk areas. No art is generated here.

signal appearance_started(area_id: String)
signal appearance_finished(area_id: String)

const DEFAULTS: Dictionary = {
	"AnimationId": "", "FramesFolder": "", "FPS": 12.0,
	"MinDelay": 6.0, "MaxDelay": 18.0, "Chance": 0.6,
	"RepeatCount": 1, "Scale": 1.0, "FlipX": false,
	"FlipY": false, "Enabled": true,
}
const BACKGROUND_Z: int = -90

@export var max_simultaneous: int = 2
@export var only_when_on_screen: bool = true
@export var random_seed: int = 0
var slots: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _active_count: int = 0


func configure(layers: Array, textures: RefCounted) -> void:
	z_as_relative = false
	z_index = BACKGROUND_Z
	y_sort_enabled = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed
	for layer: Dictionary in layers:
		if str(layer.get("__type", "")) != "Entities" or not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "AmbientArea":
				continue
			var config: Dictionary = DEFAULTS.duplicate(true)
			for field: Dictionary in entity.get("fieldInstances", []):
				var value: Variant = field.get("__value")
				if value != null:
					config[str(field.get("__identifier", ""))] = value
			var pixel: Array = entity.get("px", [0, 0])
			var pivot: Array = entity.get("__pivot", [0, 0])
			var size: Vector2 = Vector2(float(entity.get("width", 48)), float(entity.get("height", 48)))
			var position_in_map: Vector2 = Vector2(float(pixel[0]), float(pixel[1])) + offset
			var rect: Rect2 = Rect2(position_in_map - size * Vector2(float(pivot[0]), float(pivot[1])), size)
			var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
			sprite.name = "Ambient_%d" % slots.size()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.hide()
			add_child(sprite)
			sprite.add_to_group("ldtk_ambient_areas")
			var index: int = slots.size()
			slots.append({"id": str(entity.get("iid", sprite.name)), "rect": rect,
				"config": config, "sprite": sprite, "animation": &"",
				"remaining": _next_delay(config), "cycles": 0, "active": false,
				"ready": false})
			sprite.set_meta("authored_area", rect)
			sprite.set_meta("waiting_for_frames", true)
			sprite.animation_finished.connect(_on_cycle_finished.bind(index))
			sprite.animation_looped.connect(_on_cycle_finished.bind(index))
			_assign_frames(index, _frames_from_folder(config, textures))


func bind_animation(animation_id: String, frames: SpriteFrames) -> int:
	# Future assets can be bound by ID, without creating physics/gameplay entities.
	var count: int = 0
	if animation_id.is_empty():
		return count
	for index: int in range(slots.size()):
		if str((slots[index].config as Dictionary).AnimationId) == animation_id:
			_assign_frames(index, frames)
			count += 1
	return count


func _frames_from_folder(config: Dictionary, textures: RefCounted) -> SpriteFrames:
	var folder: String = str(config.FramesFolder).strip_edges().replace("\\", "/").trim_prefix("res://").trim_suffix("/")
	if folder.is_empty() or folder.is_absolute_path() or ".." in folder.split("/"):
		return null
	var directory: DirAccess = DirAccess.open("res://" + folder)
	if directory == null:
		return null
	var files: Array[String] = []
	for filename: String in directory.get_files():
		if filename.get_extension().to_lower() == "png":
			files.append(filename)
	files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var frames: SpriteFrames = SpriteFrames.new()
	frames.set_animation_loop(&"default", false)
	frames.set_animation_speed(&"default", maxf(float(config.FPS), 1.0))
	for filename: String in files:
		var texture: Texture2D = textures.call("get_texture", folder + "/" + filename) as Texture2D
		if texture != null:
			frames.add_frame(&"default", texture)
	return frames if frames.get_frame_count(&"default") > 0 else null


func _assign_frames(index: int, frames: SpriteFrames) -> void:
	var slot: Dictionary = slots[index]
	if bool(slot.active):
		_finish_appearance(slot)
	slot.ready = false
	var sprite: AnimatedSprite2D = slot.sprite as AnimatedSprite2D
	sprite.set_meta("waiting_for_frames", true)
	if frames == null:
		return
	var animation: StringName = &""
	for candidate: String in frames.get_animation_names():
		if frames.get_frame_count(candidate) > 0:
			if animation == &"":
				animation = StringName(candidate)
			if candidate == str((slot.config as Dictionary).AnimationId):
				animation = StringName(candidate)
				break
	if animation == &"":
		return
	sprite.sprite_frames = frames
	slot.animation = animation
	slot.ready = true
	sprite.set_meta("waiting_for_frames", false)
	slot.remaining = _next_delay(slot.config as Dictionary)


func _process(delta: float) -> void:
	for slot: Dictionary in slots:
		var config: Dictionary = slot.config
		if not bool(config.Enabled) or not bool(slot.ready):
			continue
		if bool(slot.active):
			if only_when_on_screen and not _is_area_visible(slot.rect as Rect2):
				_finish_appearance(slot)
			continue
		slot.remaining = float(slot.remaining) - delta
		if float(slot.remaining) > 0.0:
			continue
		slot.remaining = _next_delay(config)
		if _active_count >= maxi(max_simultaneous, 1):
			continue
		if only_when_on_screen and not _is_area_visible(slot.rect as Rect2):
			continue
		if _rng.randf() >= clampf(float(config.Chance), 0.0, 1.0):
			continue
		_show_appearance(slot)


func _is_area_visible(rect: Rect2) -> bool:
	var viewport: Viewport = get_viewport()
	var to_local_canvas: Transform2D = get_global_transform().affine_inverse() * viewport.get_canvas_transform().affine_inverse()
	var visible_rect: Rect2 = to_local_canvas * viewport.get_visible_rect()
	return rect.intersects(visible_rect)


func _show_appearance(slot: Dictionary) -> void:
	var config: Dictionary = slot.config
	var sprite: AnimatedSprite2D = slot.sprite as AnimatedSprite2D
	var rect: Rect2 = slot.rect
	var animation: StringName = slot.animation
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(animation, 0)
	var visual_scale: float = maxf(float(config.Scale), 0.01)
	var half_size: Vector2 = texture.get_size() * visual_scale * 0.5
	var margin: Vector2 = half_size.min(rect.size * 0.5)
	sprite.position = Vector2(_rng.randf_range(rect.position.x + margin.x, rect.end.x - margin.x),
		_rng.randf_range(rect.position.y + margin.y, rect.end.y - margin.y))
	sprite.scale = Vector2.ONE * visual_scale
	sprite.flip_h = bool(config.FlipX)
	sprite.flip_v = bool(config.FlipY)
	sprite.speed_scale = maxf(float(config.FPS), 1.0) / maxf(sprite.sprite_frames.get_animation_speed(animation), 0.01)
	slot.cycles = maxi(int(config.RepeatCount), 1)
	slot.active = true
	_active_count += 1
	sprite.show()
	sprite.play(animation)
	sprite.set_frame_and_progress(0, 0.0)
	appearance_started.emit(str(slot.id))


func _on_cycle_finished(index: int) -> void:
	var slot: Dictionary = slots[index]
	if not bool(slot.active):
		return
	slot.cycles = int(slot.cycles) - 1
	if int(slot.cycles) <= 0:
		_finish_appearance(slot)
	else:
		var sprite: AnimatedSprite2D = slot.sprite as AnimatedSprite2D
		sprite.play(slot.animation as StringName)
		sprite.set_frame_and_progress(0, 0.0)


func _finish_appearance(slot: Dictionary) -> void:
	var sprite: AnimatedSprite2D = slot.sprite as AnimatedSprite2D
	sprite.stop()
	sprite.hide()
	slot.active = false
	_active_count = maxi(_active_count - 1, 0)
	slot.remaining = _next_delay(slot.config as Dictionary)
	appearance_finished.emit(str(slot.id))


func _next_delay(config: Dictionary) -> float:
	var minimum: float = maxf(float(config.MinDelay), 0.1)
	var maximum: float = maxf(float(config.MaxDelay), minimum)
	return _rng.randf_range(minimum, maximum)
