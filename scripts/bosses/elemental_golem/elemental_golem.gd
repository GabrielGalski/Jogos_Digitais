extends CharacterBody2D
## Arena-local state machine: reposition, raised-arm barrage, leap, shielded special.

signal damaged(amount: float, remaining_health: float)
signal health_changed(current: float, maximum: float)
signal died(actor: Node2D)
signal barrage_started(platform: int, element_index: int)
signal special_started(sequence: int)
signal special_finished(sequence: int)
signal volley_fired(element_index: int, volley_index: int)
signal defeat_animation_finished

const ORB: Script = preload("res://scripts/bosses/elemental_golem/elemental_orb.gd")
const FLASHES: Script = preload("res://scripts/bosses/elemental_golem/arena_flashes.gd")
const ATTACK: Script = preload("res://scripts/bosses/elemental_golem/attack_frames.gd")
const FRAMES: Array[SpriteFrames] = [
	preload("res://resources/enemies/elemental_golem/ice.tres"),
	preload("res://resources/enemies/elemental_golem/fire.tres"),
	preload("res://resources/enemies/elemental_golem/lightning.tres"),
]
const STYLE: Script = preload("res://scripts/bosses/elemental_golem/elemental_style.gd")
const COLORS: Array[Color] = STYLE.COLORS
enum State { DORMANT, MOVING, CHARGING, FIRING, RECOVERING, JUMP_PREP, JUMPING, LANDING, SPECIAL, DEAD }

@export var max_health: float = 360.0
@export var barrage_duration: float = 3.6
@export var barrage_damage_limit: float = 0.15
@export var jump_duration: float = 0.8
@export var jump_height: float = 76.0
@export var walk_speed: float = 34.0
var health: float = 360.0
var state: State = State.DORMANT
var element: int = 0
var shielded: bool = false
var current_platform: int = 1
var last_firing_platform: int = -1
var special_count: int = 0
var barrage_damage: float = 0.0
var barrage_history: Array[int] = []
var target: Player = null
var layout: Node2D = null
var projectiles: Node2D = null
var sprite: AnimatedSprite2D = null
var flashes: Node2D = null
var air_height: float = 0.0
var _remaining: float = 0.0
var _shot_remaining: float = 0.0
var _barrage_elapsed: float = 0.0
var _volley: int = 0
var _barrage_serial: int = 0
var _move_target: Vector2 = Vector2.ZERO
var _jump_origin: Vector2 = Vector2.ZERO
var _jump_destination: Vector2 = Vector2.ZERO
var _special_jump: bool = false
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _hit_remaining: float = 0.0
var _defeat_finished: bool = false


func configure(actor: Player, arena_layout: Node2D, shots: Node2D) -> void:
	target = actor
	layout = arena_layout
	projectiles = shots


func _ready() -> void:
	health = max_health
	collision_layer = 4
	collision_mask = 0
	z_index = 4
	add_to_group(&"enemy_bodies")
	add_to_group(&"elemental_golem")
	_random.randomize()
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.name = "BodyCollision"
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = 18.0
	capsule.height = 42.0
	shape.shape = capsule
	shape.position = Vector2(0,-20)
	add_child(shape)
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = FRAMES[element]
	sprite.offset = Vector2(0,-32)
	sprite.scale = Vector2.ONE * 1.6
	add_child(sprite)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play(&"idle")
	position = layout.get("boss_spawn") as Vector2
	current_platform = int(layout.call("platform_at",layout.to_global(position)))
	target.defeated.connect(stop_combat)


func begin() -> void:
	if state != State.DORMANT or target.dead: return
	_move_on_platform()


func _physics_process(delta: float) -> void:
	_hit_remaining = maxf(0.0,_hit_remaining-delta)
	sprite.modulate = Color(2.0,1.65,1.9) if _hit_remaining > 0.0 else Color.WHITE
	if state == State.DEAD or state == State.DORMANT or not is_instance_valid(target) or target.dead or target.intro_locked:
		queue_redraw()
		return
	_remaining -= delta
	sprite.flip_h = target.global_position.x < global_position.x
	match state:
		State.MOVING:
			position = position.move_toward(_move_target,walk_speed*delta)
			if position.distance_to(_move_target) < 1.0: _charge_barrage()
		State.CHARGING:
			if _remaining <= 0.0: _start_barrage()
		State.FIRING:
			if _remaining <= 0.0:
				_end_barrage()
			else:
				_update_barrage(delta)
		State.RECOVERING:
			if _remaining <= 0.0: _jump_to(_choose_platform(),false)
		State.JUMP_PREP:
			if _remaining <= 0.0:
				state = State.JUMPING
				_remaining = jump_duration
		State.JUMPING:
			var progress: float = clampf(1.0-_remaining/jump_duration,0.0,1.0)
			position = _jump_origin.lerp(_jump_destination,smoothstep(0.0,1.0,progress))
			air_height = sin(progress*PI)*jump_height
			sprite.position.y = -roundf(air_height)
			(get_node("BodyCollision") as CollisionShape2D).position.y = -20.0-air_height
			if progress >= 0.5 and sprite.animation != &"fall": sprite.play(&"fall")
			if _remaining <= 0.0: _land()
		State.LANDING:
			if _remaining <= 0.0:
				if _special_jump: _launch_special()
				else: _move_on_platform()
	queue_redraw()


func _move_on_platform() -> void:
	var platforms: Array = layout.get("platforms") as Array
	var area: Rect2 = (platforms[current_platform] as Rect2).grow(-42.0)
	_move_target = Vector2(_random.randf_range(area.position.x,area.end.x),_random.randf_range(area.position.y+10.0,area.end.y))
	_move_target = layout.call("clamp_platform_point",_move_target,current_platform) as Vector2
	state = State.MOVING
	sprite.play(&"walk")


func _choose_platform() -> int:
	var choices: Array[int] = []
	for index: int in range(9):
		if index != current_platform and index != last_firing_platform: choices.append(index)
	return choices[_random.randi_range(0,choices.size()-1)]


func _charge_barrage() -> void:
	element = (element+1)%3
	sprite.sprite_frames = FRAMES[element]
	sprite.play(&"charge")
	state = State.CHARGING
	_remaining = ATTACK.CHARGE_DURATION


func _start_barrage() -> void:
	# This guard also protects future interruption/recovery paths from repeats.
	if current_platform == last_firing_platform:
		_jump_to(_choose_platform(),false)
		return
	state = State.FIRING
	_remaining = barrage_duration
	_barrage_elapsed = 0.0
	_shot_remaining = ATTACK.VOLLEY_INTERVALS[element] * float(ATTACK.SLAM_IMPACT_FRAME) / float(sprite.sprite_frames.get_frame_count(&"slam"))
	barrage_damage = 0.0
	_volley = 0
	_barrage_serial += 1
	last_firing_platform = current_platform
	barrage_history.append(current_platform)
	_set_barrage_pose(0) # Pose 6 leads straight into the first ground contact.
	barrage_started.emit(current_platform,element)


func _set_barrage_pose(frame: int) -> void:
	sprite.animation = &"slam"
	sprite.pause() # Physics owns both the pose and projectile release clock.
	sprite.set_frame_and_progress(frame,0.0)


func _update_barrage(delta: float) -> void:
	_barrage_elapsed += delta
	_shot_remaining -= delta
	while _shot_remaining <= 0.0:
		_set_barrage_pose(ATTACK.SLAM_IMPACT_FRAME)
		_fire_volley()
		if state != State.FIRING: return
	var count: int = sprite.sprite_frames.get_frame_count(&"slam")
	var phase: float = fposmod(_barrage_elapsed/ATTACK.VOLLEY_INTERVALS[element],1.0)
	_set_barrage_pose(mini(floori(phase*float(count)),count-1))


func _fire_volley() -> void:
	var aim: Vector2 = (global_position+ATTACK.MUZZLE).direction_to(target.global_position)
	match element:
		0: # Ice: rotating spokes leave wide angular lanes.
			for index: int in range(8):
				_spawn_orb(Vector2.from_angle(aim.angle()+float(index)*TAU/8.0+float(_volley)*0.13),104.0)
		1: # Fire: measured three-orb fans aimed once at the start of each volley.
			for offset: float in [-0.20,0.0,0.20]: _spawn_orb(aim.rotated(offset),124.0)
		2: # Lightning: one measured alternating bolt per ground impact.
			_spawn_orb(aim.rotated(0.09 if _volley%2 == 0 else -0.09),132.0)
	_shot_remaining += ATTACK.VOLLEY_INTERVALS[element]
	volley_fired.emit(element,_volley)
	_volley += 1


func _spawn_orb(forward: Vector2, speed: float) -> void:
	var orb: Node2D = ORB.new() as Node2D
	orb.set("target",target)
	orb.set("caster",self)
	orb.set("element",element)
	orb.set("direction",forward)
	orb.set("speed",speed)
	orb.position = global_position + ATTACK.MUZZLE + forward*18.0
	orb.set_meta(&"barrage_serial",_barrage_serial)
	projectiles.add_child(orb)
	orb.connect("damage_dealt",_on_orb_damage.bind(_barrage_serial))


func _on_orb_damage(amount: float, serial: int) -> void:
	if state != State.FIRING or serial != _barrage_serial: return
	barrage_damage += amount
	if barrage_damage >= target.max_health*barrage_damage_limit-0.001:
		_end_barrage()
		for shot: Node in projectiles.get_children():
			if int(shot.get_meta(&"barrage_serial",-1)) == serial and not bool(shot.get("reflected")):
				shot.call("dismiss")


func _end_barrage() -> void:
	state = State.RECOVERING
	_remaining = 0.45
	sprite.play(&"idle")


func _jump_to(platform: int, for_special: bool) -> void:
	current_platform = platform
	_special_jump = for_special
	_jump_origin = position
	var platforms: Array = layout.get("platforms") as Array
	_jump_destination = (platforms[platform] as Rect2).get_center()
	_jump_destination = layout.call("clamp_platform_point",_jump_destination,platform) as Vector2
	layout.set("landing_point",layout.to_global(_jump_destination))
	state = State.JUMP_PREP
	_remaining = 0.25
	sprite.play(&"jump_prepare") # Authored attack poses 3 and 4.


func _land() -> void:
	position = _jump_destination
	air_height = 0.0
	sprite.position.y = 0.0
	(get_node("BodyCollision") as CollisionShape2D).position.y = -20.0
	layout.call("landing_impact",global_position)
	state = State.LANDING
	_remaining = 0.24
	sprite.play(&"fall") # Authored pose 7 on the descent and landing.


func _begin_special() -> void:
	special_count += 1
	shielded = true
	clear_attacks()
	element = (special_count-1)%3
	sprite.sprite_frames = FRAMES[element]
	_jump_to(4,true)
	special_started.emit(special_count)


func _launch_special() -> void:
	state = State.SPECIAL
	sprite.play(&"idle")
	flashes = FLASHES.new() as Node2D
	flashes.name = "ArenaFlashes"
	flashes.call("configure",target,layout,element,special_count)
	projectiles.add_child(flashes)
	flashes.connect("finished",_finish_special)


func _finish_special() -> void:
	flashes = null
	if state == State.DEAD or target.dead: return
	shielded = false
	_special_jump = false
	state = State.RECOVERING
	_remaining = 0.6
	special_finished.emit(special_count)


func take_damage(amount: float) -> void:
	if not is_alive() or shielded or amount <= 0.0 or state == State.DORMANT: return
	var previous: float = health
	var threshold: float = max_health*(0.75-float(special_count)*0.25) if special_count < 3 else 0.0
	# A phase boundary absorbs the overflow, so even a huge hit cannot skip a special.
	health = maxf(threshold,health-amount)
	_hit_remaining = 0.10
	health_changed.emit(health,max_health)
	damaged.emit(previous-health,health)
	if health <= 0.0:
		_enter_defeated()
	elif special_count < 3 and health <= threshold:
		_begin_special()


func _disable_combat_body() -> void:
	collision_layer = 0
	collision_mask = 0
	(get_node("BodyCollision") as CollisionShape2D).set_deferred("disabled",true)
	remove_from_group(&"enemy_bodies")
	remove_from_group(&"elemental_golem")
	velocity = Vector2.ZERO
	layout.set("landing_point",Vector2.INF)
	clear_attacks()


func _enter_defeated() -> void:
	state = State.DEAD
	shielded = false
	_hit_remaining = 0.0
	_disable_combat_body()
	# The death finishes on the floor at the actual defeat position, even in a leap.
	air_height = 0.0
	sprite.position = Vector2.ZERO
	sprite.modulate = Color.WHITE
	sprite.play(&"die")
	died.emit(self)
	queue_redraw()


func _on_animation_finished() -> void:
	if state == State.DEAD and sprite.animation == &"die": _finish_defeat()


func _finish_defeat() -> void:
	if _defeat_finished: return
	_defeat_finished = true
	sprite.animation = &"die"
	sprite.set_frame_and_progress(sprite.sprite_frames.get_frame_count(&"die")-1,0.0)
	sprite.pause()
	set_physics_process(false)
	defeat_animation_finished.emit()


func restore_defeated() -> void:
	# A later visit contains no new enemy or replay of its death.
	state = State.DEAD
	health = 0.0
	_defeat_finished = true
	_disable_combat_body()
	sprite.pause()
	set_physics_process(false)
	hide()


func clear_attacks() -> void:
	if not is_instance_valid(projectiles): return
	for shot: Node in projectiles.get_children():
		if shot.has_method("dismiss"): shot.call("dismiss")
		elif shot.has_method("cancel"): shot.call("cancel")
	flashes = null


func stop_combat() -> void:
	clear_attacks()
	if state == State.DEAD: _finish_defeat()
	set_physics_process(false)
	sprite.pause()
	layout.set("landing_point",Vector2.INF)


func is_alive() -> bool:
	return state != State.DEAD and health > 0.0


func get_current_health() -> float:
	return health


func get_combat_faction() -> StringName:
	return &"monsters"


func get_projectile_hurt_capsule() -> Dictionary:
	return {"center":Vector2(0,-25.0-air_height),"radius":21.0,"height":52.0}


func receive_impact(_direction: Vector2, _impulse: float, _recovery: float = 0.055) -> void:
	pass # The boss cannot be pushed off a platform by the player's weapon.


func _draw() -> void:
	if state == State.DEAD: return
	draw_ellipse_shadow()
	if shielded:
		var tint: Color = COLORS[element]
		var center: Vector2 = Vector2(0,-30.0-air_height)
		# Thin energized rim; no opaque polygon covering the sprite.
		var rim: PackedVector2Array = PackedVector2Array()
		for index: int in range(97):
			var angle: float = float(index)*TAU/96.0
			rim.append(center+Vector2.from_angle(angle)*Vector2(39,43))
		for layer: int in range(4,0,-1):
			draw_polyline(rim,Color(tint,0.025),float(layer)*2.0,true)
		draw_polyline(rim,Color(tint,0.55),1.2,true)
		var sheen: PackedVector2Array = PackedVector2Array()
		for index: int in range(25):
			var angle: float = PI*1.05+float(index)*PI/48.0
			sheen.append(center+Vector2.from_angle(angle)*Vector2(39,43))
		draw_polyline(sheen,Color(STYLE.CORE,0.7),0.65,true)


func draw_ellipse_shadow() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(20): points.append(Vector2.from_angle(float(index)*TAU/20.0)*Vector2(24,7))
	draw_colored_polygon(points,Color(0.04,0.03,0.08,0.5-air_height/jump_height*0.25))
