extends RefCounted

const IDLE: Texture2D = preload("res://assets/enemies/vampire/Vampires3_Idle_full.png")
const RUN: Texture2D = preload("res://assets/enemies/vampire/Vampires3_Run_full.png")
const ATTACK: Texture2D = preload("res://assets/enemies/vampire/Vampires3_Attack_full.png")
const HURT: Texture2D = preload("res://assets/enemies/vampire/Vampires3_Hurt_full.png")
const DEATH: Texture2D = preload("res://assets/enemies/vampire/Vampires3_Death_full.png")
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]
const CELL: Vector2 = Vector2(64, 64)


static func build_frames() -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation(&"default")
	for row: int in range(DIRECTIONS.size()):
		_add(frames, &"idle", IDLE, row, 0, 4, 6.0, true)
		_add(frames, &"run", RUN, row, 0, 8, 17.0, true)
		_add(frames, &"attack", ATTACK, row, 0, 12, 11.0, false)
		_add(frames, &"hurt", HURT, row, 0, 4, 15.0, false)
		_add(frames, &"death", DEATH, row, 0, 11, 12.0, false)
		_add(frames, &"smoke", DEATH, row, 7, 4, 18.0, false)
	return frames


static func facing(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "left" if direction.x < 0.0 else "right"
	return "up" if direction.y < 0.0 else "down"


static func _add(frames: SpriteFrames, action: StringName, sheet: Texture2D, row: int,
		first: int, count: int, fps: float, loop: bool) -> void:
	var clip: StringName = StringName("%s_%s" % [action, DIRECTIONS[row]])
	frames.add_animation(clip)
	frames.set_animation_speed(clip, fps)
	frames.set_animation_loop(clip, loop)
	for column: int in range(first, first + count):
		var texture: AtlasTexture = AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(Vector2(column, row) * CELL, CELL)
		texture.filter_clip = true
		frames.add_frame(clip, texture)
