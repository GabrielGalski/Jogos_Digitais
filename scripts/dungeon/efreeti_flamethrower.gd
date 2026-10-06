extends Node2D
## M08 preview: the old persistent flamethrower geometry, driven by CardAttack.

const FLAME_START: Color = Color("#fffc40")
const FLAME_GOLD: Color = Color("#ffd541")
const FLAME_ORANGE: Color = Color("#fa6a0a")
const FLAME_RED: Color = Color("#df3e23")

@export var reach: float = 128.0
@export var initial_reach: float = 16.0
@export var initial_half_width: float = 5.0
@export var tip_half_width: float = 17.0

var mode: StringName = &"M08"
var source: Marker2D
var cursor_world: Callable
var firing: bool = false
var firing_age: float = 0.0
var idle_age: float = 0.0
var expansion_speed: float = 340.0
var particle_lifetime: float = 0.38
var jet: CPUParticles2D
var sparks: CPUParticles2D


func _ready() -> void:
	add_to_group(&"manifestation_projectiles")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 3
	var particle_texture: Texture2D = _make_particle_texture()
	jet = _make_emitter(144, particle_texture, 6.5, 0.65, 1.20)
	jet.name = "Jet"
	sparks = _make_emitter(32, particle_texture, 8.0, 0.20, 0.40)
	sparks.name = "EdgeSparks"
	sparks.angular_velocity_min = -110.0
	sparks.angular_velocity_max = 110.0


func setup(muzzle: Marker2D, aim: Callable, snapshot: CardAttack) -> void:
	source = muzzle
	cursor_world = aim
	expansion_speed = snapshot.projectile_speed
	particle_lifetime = snapshot.projectile_lifetime
	jet.lifetime = particle_lifetime
	sparks.lifetime = particle_lifetime
	follow_source()
	start_firing()


func start_firing() -> void:
	if firing or is_queued_for_deletion():
		return
	firing = true
	firing_age = 0.0
	idle_age = 0.0
	jet.emitting = true
	sparks.emitting = true


func stop_firing() -> void:
	if not firing:
		return
	firing = false
	idle_age = 0.0
	jet.emitting = false
	sparks.emitting = false


func _physics_process(delta: float) -> void:
	if not is_instance_valid(source):
		queue_free()
		return
	if not firing:
		idle_age += delta
		if idle_age >= particle_lifetime + 0.08:
			queue_free()
		return
	follow_source()
	firing_age += delta


func follow_source() -> void:
	if not is_instance_valid(source):
		return
	global_position = source.global_position
	var cursor: Vector2 = cursor_world.call()
	var aim: Vector2 = cursor - global_position
	if aim.is_zero_approx():
		aim = Vector2.RIGHT
	global_rotation = aim.angle()


func contains_target(point: Vector2) -> bool:
	var local_target: Vector2 = to_local(point)
	# The hit region advances with the flame instead of reaching full length at once.
	var live_reach: float = minf(reach, firing_age * expansion_speed)
	if local_target.x < -initial_reach or local_target.x > live_reach:
		return false
	var half_width: float = lerpf(initial_half_width, tip_half_width, maxf(local_target.x, 0.0) / reach)
	return absf(local_target.y) <= half_width


func apply_channel_hit(attack: CardAttack, effects: CombatEffects) -> bool:
	if not firing or attack == null or not is_instance_valid(effects):
		return false
	var hit_any: bool = false
	var aim_direction: Vector2 = Vector2.RIGHT.rotated(global_rotation)
	for candidate: Node in get_tree().get_nodes_in_group(&"enemy_bodies"):
		var enemy: Node2D = candidate as Node2D
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if not enemy.has_method(&"is_alive") or not bool(enemy.call(&"is_alive")):
			continue
		if not contains_target(enemy.global_position):
			continue
		attack.apply_primary_hit(enemy, enemy.global_position, aim_direction, effects)
		hit_any = true
	return hit_any


func _make_emitter(amount: int, particle_texture: Texture2D, spread_degrees: float, minimum_scale: float, maximum_scale: float) -> CPUParticles2D:
	var emitter: CPUParticles2D = CPUParticles2D.new()
	emitter.emitting = false
	emitter.amount = amount
	emitter.lifetime = particle_lifetime
	emitter.local_coords = false
	emitter.direction = Vector2.RIGHT
	emitter.spread = spread_degrees
	emitter.gravity = Vector2.ZERO
	emitter.initial_velocity_min = 315.0
	emitter.initial_velocity_max = 335.0
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emitter.emission_rect_extents = Vector2(0.0, 1.5)
	emitter.scale_amount_min = minimum_scale
	emitter.scale_amount_max = maximum_scale
	emitter.texture = particle_texture
	emitter.use_fixed_seed = true
	emitter.seed = 2667 + amount
	emitter.fixed_fps = 60
	var growth: Curve = Curve.new()
	growth.add_point(Vector2(0.0, 0.35))
	growth.add_point(Vector2(0.18, 0.75))
	growth.add_point(Vector2(0.65, 1.0))
	growth.add_point(Vector2(1.0, 0.30))
	emitter.scale_amount_curve = growth
	var fade: Gradient = Gradient.new()
	var spent_red: Color = FLAME_RED
	spent_red.a = 0.0
	fade.set_color(0, FLAME_START)
	fade.set_color(1, spent_red)
	fade.add_point(0.24, FLAME_GOLD)
	fade.add_point(0.58, FLAME_ORANGE)
	fade.add_point(0.82, FLAME_RED)
	emitter.color_ramp = fade
	add_child(emitter)
	return emitter


func _make_particle_texture() -> ImageTexture:
	# White pixels allow the color ramp to supply the exact four fire colors.
	var pixels: Image = Image.create(9, 9, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	for y: int in range(9):
		for x: int in range(9):
			var dx: int = absi(x - 4)
			var dy: int = absi(y - 4)
			if dx + dy <= 5 and dx <= 3 and dy <= 3:
				pixels.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(pixels)
