extends "res://scripts/combat/projectiles/flying_eye_orb.gd"

const FIRE_IMPACT: Texture2D = preload("res://assets/enemies/open_world_horde/batilisk/effects/sprFireExplosion.png")
var sheet: Texture2D
var frames: int
var fire_impact: bool
var art: Sprite2D


func _ready() -> void:
	super()
	remove_from_group(&"flying_eye_orbs")
	material = null
	art = Sprite2D.new()
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.texture = sheet
	art.hframes = frames
	add_child(art)
	_update_art()


func _physics_process(delta: float) -> void:
	super(delta)
	if not consumed:
		_update_art()


func _update_art() -> void:
	art.frame = int(_age * 16.0) % frames
	art.position.y = -8.0 - _visual_height
	art.rotation = direction.angle()


func _impact() -> void:
	if fire_impact:
		var burst: Sprite2D = Sprite2D.new()
		burst.texture = FIRE_IMPACT
		burst.hframes = 4
		burst.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		burst.z_index = z_index
		get_parent().add_child(burst)
		burst.global_position = art.global_position
		var animation: Tween = burst.create_tween()
		animation.tween_method(func(index: int) -> void: burst.frame = index, 0, 3, 0.16)
		animation.tween_callback(burst.queue_free)
	super()


func _draw() -> void:
	pass
