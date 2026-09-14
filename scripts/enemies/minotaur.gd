class_name Minotaur
extends CharacterBody2D
## MVP presentation and hit reactions, driven by the shared chamber AI.
signal died(enemy: Minotaur)
signal damaged(amount: float, remaining_health: float)
const MELEE: PackedScene = preload("res://scenes/enemies/attacks/minotaur_melee_attack.tscn")
@export var movement_speed: float = 38.0
@export var max_resistance: float = 6.0
@export var attack_range: float = 44.0
@export var attack_windup: float = 0.38
@export var attack_interval: float = 2.0
@export var empowered_attack_windup: float = 0.18
@export var empowered_attack_interval: float = 0.55
@export var empowered_attack_duration: float = 0.38
@export var empowered_knockback: float = 140.0
var target: Player
var resistance: float = 6.0
var dying: bool = false
var last_hit_direction: Vector2 = Vector2.ZERO
var hit_velocity: Vector2 = Vector2.ZERO
var hit_recovery: float = 0.0
var spawn_grace: float = 0.5
var attack_time: float = -1.0
var attack_emitted: bool = false
var empowered: bool = false
var sense_left: float = 0.0
var observation: EnemyAIObservation
var damage_tween: Tween
var impact_tween: Tween
var hit_material: ShaderMaterial
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var brain: MinotaurAI = $AI
@onready var sensor: EnemyAIWorldSensor2D = $WorldSensor
@onready var body_shape: CollisionShape2D = $BodyCollision

func _ready() -> void:
	resistance = max_resistance
	add_to_group(&"minotaurs")
	add_to_group(&"enemy_ai_actor")
	add_to_group(&"enemy_bodies")
	hit_material = ShaderMaterial.new()
	hit_material.shader = preload("res://shaders/white_damage_flash.gdshader")
	sprite.material = hit_material
	sprite.play(&"walk")
	brain.minion_profile.attack_range = attack_range - sensor.attack_slot_radius
	brain.minion_profile.attack_cooldown = attack_interval
	brain.minion_profile.personal_space = 5.0
	brain.minion_profile.target_acquisition_radius = 1000.0
	sensor.actor_role = EnemyAIEnums.Role.MELEE
	sense_left = float(get_instance_id() % 12) * 0.01
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)

func setup(player: Player, chamber: Node2D, bounds: Rect2) -> void:
	target = player
	sensor.configure(chamber, bounds)

func set_empowered(enabled: bool) -> void:
	empowered = enabled
	if empowered:
		brain.apply_elite_influence(&"asterion")
		brain.minion_profile.attack_cooldown = empowered_attack_interval
		sprite.speed_scale = 1.5
	else:
		brain.clear_elite_influence()
		brain.minion_profile.attack_cooldown = attack_interval
		sprite.speed_scale = 1.0
func is_alive() -> bool:
	return not dying and resistance > 0.0

func get_current_health() -> float:
	return resistance

func get_separation_radius() -> float:
	return 13.0

func take_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0:
		return
	resistance = maxf(0.0, resistance - amount)
	damaged.emit(amount, resistance)
	if damage_tween and damage_tween.is_valid():
		damage_tween.kill()
	hit_material.set_shader_parameter(&"flash_amount", 0.85)
	damage_tween = create_tween()
	damage_tween.tween_interval(0.035)
	damage_tween.tween_method(_set_flash, 0.85, 0.0, 0.075)
	if resistance <= 0.0:
		_die()

func _set_flash(value: float) -> void:
	hit_material.set_shader_parameter(&"flash_amount", value)

func receive_impact(direction: Vector2, impulse: float, recovery: float = 0.055) -> void:
	if not is_alive():
		return
	last_hit_direction = direction.normalized()
	hit_velocity = (hit_velocity + last_hit_direction * impulse).limit_length(180.0)
	hit_recovery = maxf(hit_recovery, recovery)
	attack_time = -1.0
	set_meta(&"enemy_ai_is_attacking", false)
	sprite.play(&"walk")
	if impact_tween and impact_tween.is_valid():
		impact_tween.kill()
	var compression: float = clampf(impulse / 850.0, 0.045, 0.19)
	sprite.scale = Vector2(1.0 + compression, 1.0 - compression)
	sprite.rotation = last_hit_direction.x * compression * 0.65
	impact_tween = create_tween().set_parallel(true)
	impact_tween.tween_property(sprite, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	impact_tween.tween_property(sprite, "rotation", 0.0, 0.16)

func _die() -> void:
	dying = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	set_meta(&"enemy_ai_is_attacking", false)
	body_shape.set_deferred("disabled", true)
	remove_from_group(&"minotaurs")
	remove_from_group(&"enemy_ai_actor")
	remove_from_group(&"enemy_bodies")
	died.emit(self)
	var death: Tween = create_tween().set_parallel(true)
	death.tween_property(sprite, "position", last_hit_direction * 9.0, 0.11).set_ease(Tween.EASE_OUT)
	death.tween_property(self, "scale", scale * 0.72, 0.11)
	death.tween_property(self, "modulate:a", 0.0, 0.11)
	death.chain().tween_callback(queue_free)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or target.intro_locked:
		velocity = Vector2.ZERO
		return
	spawn_grace = maxf(0.0, spawn_grace - delta)
	if spawn_grace > 0.0:
		return
	hit_recovery = maxf(0.0, hit_recovery - delta)
	if hit_velocity.length_squared() > 1.0:
		velocity = hit_velocity
		move_and_slide()
		hit_velocity *= exp(-16.0 * delta)
	if hit_recovery > 0.0:
		return
	var to_target: Vector2 = target.global_position - global_position
	if absf(to_target.x) > 0.05:
		sprite.flip_h = to_target.x < 0.0
	if attack_time >= 0.0:
		_update_attack(delta)
		return
	sense_left -= delta
	if sense_left <= 0.0 or observation == null:
		observation = sensor.build_observation(self, target, EnemyAIEnums.Objective.PRESSURE_TARGET, attack_range, false, 0.12)
		sense_left = 0.12
		brain.reset_decision_timer()
	var decision: EnemyAIDecision = brain.evaluate(observation, delta)
	set_meta(&"enemy_ai_intent", decision.intent)
	if decision.intent == EnemyAIEnums.Intent.PREPARE and to_target.length() <= attack_range and sensor._has_line_of_sight(self, target, target.global_position):
		velocity = Vector2.ZERO if not empowered else sensor.safe_velocity(self, to_target.normalized() * movement_speed * brain.speed_multiplier(), delta)
		if empowered:
			move_and_slide()
		attack_time = 0.0
		attack_emitted = false
		set_meta(&"enemy_ai_is_attacking", true)
		sprite.play(&"attack")
		return
	velocity = Vector2.ZERO if decision.lock_movement else sensor.safe_velocity(self, decision.movement_direction * movement_speed * brain.speed_multiplier(), delta)
	move_and_slide()
	if sprite.animation != &"walk":
		sprite.play(&"walk")

func _update_attack(delta: float) -> void:
	attack_time += delta
	if empowered and is_instance_valid(target):
		var charge_direction: Vector2 = global_position.direction_to(target.global_position)
		velocity = sensor.safe_velocity(self, charge_direction * movement_speed * brain.speed_multiplier(), delta)
		move_and_slide()
	var current_windup: float = empowered_attack_windup if empowered else attack_windup
	if attack_time >= current_windup and not attack_emitted:
		attack_emitted = true
		var direction: Vector2 = global_position.direction_to(target.global_position)
		var attack: Node2D = MELEE.instantiate() as Node2D
		add_child(attack)
		attack.position = direction * 17.0
		attack.call(&"setup", target, self, direction, attack_range, empowered_knockback if empowered else 0.0)
	var attack_duration: float = empowered_attack_duration if empowered else 0.6
	if attack_time >= attack_duration:
		attack_time = -1.0
		set_meta(&"enemy_ai_is_attacking", false)
		var current_interval: float = empowered_attack_interval if empowered else attack_interval
		brain.notify_attack_committed(maxf(0.0, current_interval - attack_duration))
		sprite.play(&"walk")


