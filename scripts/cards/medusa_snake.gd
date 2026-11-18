extends CharacterBody2D
var service: Node
var target: Node2D
var bites: int = 0
var age: float = 0.0
var cooldown: float = 0.0
var dying: bool = false
var visual: AnimatedSprite2D
static var animation_frames: SpriteFrames


func _ready() -> void:
	add_to_group(&"medusa_snakes")
	collision_layer = 0
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 4.0
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)
	if animation_frames == null:
		animation_frames = SpriteFrames.new()
		for state: String in ["walk", "attack", "defeat"]:
			animation_frames.add_animation(state)
			animation_frames.set_animation_loop(state, state == "walk")
			animation_frames.set_animation_speed(state, 12.0)
			for index: int in range(8 if state == "walk" else 6):
				animation_frames.add_frame(state, load("res://assets/summons/medusa_snake/%s/%s_%02d.png" % [state, state, index + 1]) as Texture2D)
	visual = AnimatedSprite2D.new()
	visual.sprite_frames = animation_frames
	visual.position.y = -15.0
	add_child(visual)
	visual.animation_finished.connect(_animation_finished)
	visual.play(&"walk")


func _physics_process(delta: float) -> void:
	age += delta
	if dying:
		return
	if age >= 6.0 or not is_instance_valid(service):
		_defeat()
		return
	if not is_instance_valid(target) or not service.call("valid_enemy", target):
		target = service.call("nearest_enemy", global_position, 300.0) as Node2D
	var height: float = float(service.call("height_at", global_position))
	visual.position.y = -15.0 - height
	if not is_instance_valid(target):
		return
	visual.flip_h = target.global_position.x < global_position.x
	cooldown = maxf(0.0, cooldown - delta)
	if visual.animation == &"attack" and visual.is_playing():
		return
	if global_position.distance_to(target.global_position) <= 20.0 and cooldown <= 0.0:
		bites += 1
		cooldown = 0.65
		visual.play(&"attack")
		service.call("poison", target, 1.0, 3.0, null)
		service.call("mutation_hit", target, 3.0)
		return
	var direction: Vector2 = service.call("companion_direction", global_position, target.global_position) as Vector2
	velocity = direction * 95.0
	if service.call("has_floor", global_position + velocity * delta):
		move_and_slide()
	if visual.animation != &"walk":
		visual.play(&"walk")


func _animation_finished() -> void:
	if visual.animation == &"defeat":
		queue_free()
	elif bites >= 3:
		_defeat()
	else:
		visual.play(&"walk")


func _defeat() -> void:
	if dying:
		return
	dying = true
	velocity = Vector2.ZERO
	visual.play(&"defeat")
