extends "res://scripts/combat/projectiles/flying_eye_orb.gd"
## Blood serpents keep the normal swept projectile, dodge and parry rules.

const COIL: Texture2D = preload("res://assets/enemies/vampire/frames/attack_magic/right/06.png")
const STRIKE: Texture2D = preload("res://assets/enemies/vampire/frames/attack_magic/right/07.png")
const COIL_REGION: Rect2 = Rect2(21, 21, 29, 15)
const STRIKE_REGION: Rect2 = Rect2(27, 20, 24, 17)
const WAVE_RATE: float = 7.6
const WAVE_WIDTH: float = 8.5
var wave_sign: float = 1.0
var _heading: Vector2 = Vector2.RIGHT


func _ready() -> void:
	super._ready()
	remove_from_group(&"flying_eye_orbs")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_heading = direction


func _flight_motion(delta: float) -> Vector2:
	var motion: Vector2 = super._flight_motion(delta)
	if not reflected:
		var offset_change: float = sin(_age * WAVE_RATE) - sin((_age - delta) * WAVE_RATE)
		motion += direction.orthogonal() * offset_change * WAVE_WIDTH * wave_sign
	if not motion.is_zero_approx():
		_heading = motion.normalized()
	return motion


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, _heading.angle(), Vector2.ONE)
	var thrust: bool = floori(_age * 13.0) % 2 == 1
	var texture: Texture2D = STRIKE if thrust else COIL
	var region: Rect2 = STRIKE_REGION if thrust else COIL_REGION
	var shade: Color = Color("#ffd794") if reflected else Color.WHITE
	# The head sits over the contact circle, with the rest of the art trailing behind.
	draw_texture_rect_region(texture, Rect2(Vector2(-13.0, -4.5), Vector2(17.0, 9.0)), region, shade)
	draw_set_transform(Vector2.ZERO)
