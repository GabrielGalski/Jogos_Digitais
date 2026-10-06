extends Node2D
## Flight and presentation only; the original weapon still owns combat.
const FRONT: Texture2D = preload("res://assets/weapons/booster/looking_straight.png")
const LEFT: Texture2D = preload("res://assets/weapons/booster/look_left.png")
const RIGHT: Texture2D = preload("res://assets/weapons/booster/look_right.png")
const BACK: Texture2D = preload("res://assets/weapons/booster/back.png")
const EDGE_SHADER: Shader = preload("res://shaders/caster_edges.gdshader")
@export var body_scale: float = 0.18
@export var follow_response: float = 7.0
var host: Node2D
var player: Player
var face: Sprite2D
var shadow: Polygon2D
var flight_position: Vector2
var hover_time: float = 0.0
var shoulder: float = 1.0
var vertical_side: float = -1.0
var crossing_time: float = 0.0
var initialized: bool = false

func configure(weapon_host: Node2D) -> void:
	host = weapon_host
	player = host.get_parent() as Player
	# Render independently from the player's inherited Z order.
	top_level = true
	z_as_relative = false
	z_index = player.z_index
	var player_body: AnimatedSprite2D = player.get_node("Body") as AnimatedSprite2D
	player_body.z_index = 1
	face = Sprite2D.new()
	face.name = "Face"
	face.texture = FRONT
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var edge_material: ShaderMaterial = ShaderMaterial.new()
	edge_material.shader = EDGE_SHADER
	face.material = edge_material
	add_child(face)
	shadow = Polygon2D.new()
	shadow.name = "GroundShadow"
	shadow.color = Color(0.08, 0.03, 0.10, 0.25)
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(16):
		var angle: float = float(index) * TAU / 16.0
		points.append(Vector2(cos(angle) * 4.0, sin(angle) * 1.5))
	shadow.polygon = points
	shadow.show_behind_parent = true
	add_child(shadow)

func update_pose(delta: float) -> void:
	hover_time += delta
	var mouse: Vector2 = host.call(&"get_aim_world_position")
	var locked: bool = bool(host.get("cutscene_pose_active")) or player.intro_locked
	var aim: Vector2 = Vector2.RIGHT if locked else (mouse - player.global_position).normalized()
	if aim.is_zero_approx():
		aim = Vector2.RIGHT * shoulder
	var attacking: bool = not locked and bool(host.get("combat_enabled")) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var desired_side: float = shoulder
	# Aim selects one of four positions even when the player is not firing.
	if not locked and absf(aim.x) > 0.22:
		desired_side = signf(aim.x)
	elif absf(player.velocity.x) > 4.0:
		desired_side = -signf(player.velocity.x)
	if locked:
		vertical_side = -1.0
	elif absf(aim.y) > 0.22:
		vertical_side = signf(aim.y)
	if desired_side != shoulder:
		shoulder = desired_side
		crossing_time = 0.35
	crossing_time = maxf(crossing_time - delta, 0.0)
	var offset: Vector2 = Vector2(shoulder * (21.0 if attacking else 16.0), vertical_side * 10.0)
	if attacking:
		offset.y += aim.y * 4.0
	if crossing_time > 0.0:
		offset.y -= 9.0
	var desired: Vector2 = player.global_position + offset
	# Only actual teleports reset the follower; a dash must leave it trailing behind.
	if not initialized or flight_position.distance_to(player.global_position) > 180.0:
		flight_position = desired
		initialized = true
	var response: float = follow_response * (0.5 if player.is_dashing() else 1.0)
	flight_position = flight_position.lerp(desired, 1.0 - exp(-response * delta))
	flight_position = _clear_position(player.global_position, flight_position)
	var pulse: float = float(host.get("shot_recoil"))
	host.set("shot_recoil", move_toward(pulse, 0.0, delta / 0.10))
	global_position = _clear_position(player.global_position, flight_position + Vector2(0.0, sin(hover_time * 3.0) * 1.2) - aim * pulse * 2.2)
	face.texture = BACK if aim.y < -0.65 else FRONT if aim.y > 0.65 else LEFT if aim.x < 0.0 else RIGHT
	face.scale = Vector2(1.0 - pulse * 0.09, 1.0 + pulse * 0.08) * body_scale
	face.rotation = clampf((desired.x - flight_position.x) * 0.006, -0.1, 0.1)
	shadow.position = Vector2(0.0, 13.0 - sin(hover_time * 3.0) * 1.2)
	var muzzle_position: Vector2 = global_position
	var muzzle: Marker2D = host.get_node("WeaponPivot/Muzzle") as Marker2D
	muzzle.global_position = muzzle_position
	host.set("aim_direction", aim if locked else (mouse - muzzle_position).normalized())

func _clear_position(origin: Vector2, destination: Vector2) -> Vector2:
	var arena: Node2D = player.get_parent() as Node2D
	var bounds: Rect2 = player.movement_bounds.grow(-3.0)
	var limited: Vector2 = arena.to_global(arena.to_local(destination).clamp(bounds.position, bounds.end))
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, limited, 1, [player.get_rid()])
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return limited
	var contact: Vector2 = hit["position"]
	return contact.move_toward(origin, 5.0)
