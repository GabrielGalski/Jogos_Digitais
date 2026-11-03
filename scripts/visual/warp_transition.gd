extends CanvasLayer
## Reusable arrival/departure choreography. Arena owns room loading and travel validation.

signal finished(arriving: bool)
const BEAM: Script = preload("res://scripts/visual/warp_beam.gd")
const FADE: Shader = preload("res://shaders/warp_fade.gdshader")
const CHARACTER: Shader = preload("res://shaders/warp_character.gdshader")
@export var arrival_duration: float = 0.6
@export var departure_duration: float = 0.4
var running: bool = false
var elapsed: float = 0.0
var _arriving: bool = true
var _actor: Player = null
var _beam: Node2D = null
var _cover: ColorRect = null
var _fade_material: ShaderMaterial = null
var _character_material: ShaderMaterial = null
var _original_material: Material = null
var _shadows: Array[CanvasItem] = []
var _shadow_visibility: Array[bool] = []
var _weapon: CanvasItem = null
var _weapon_color: Color = Color.WHITE


func _ready() -> void:
	layer = 110
	_cover = ColorRect.new()
	_cover.name = "WarpFade"
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_material = ShaderMaterial.new()
	_fade_material.shader = FADE
	_cover.material = _fade_material
	add_child(_cover)
	_character_material = ShaderMaterial.new()
	_character_material.shader = CHARACTER
	_beam = BEAM.new() as Node2D
	_beam.name = "WarpBeam"
	_beam.z_index = 40
	_beam.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_parent().add_child(_beam)
	_beam.hide()


func play(arriving: bool, actor: Player) -> void:
	_restore_actor()
	_actor = actor
	_arriving = arriving
	elapsed = 0.0
	running = true
	_actor.intro_locked = true
	_actor.velocity = Vector2.ZERO
	_actor.knockback_velocity = Vector2.ZERO
	_actor.dash_remaining = 0.0
	_actor.body.end_roll()
	_original_material = _actor.body.material
	_actor.body.material = _character_material
	_weapon = _actor.get_node_or_null("BoosterShooter") as CanvasItem
	if _weapon != null:
		_weapon_color = _weapon.modulate
	for child_name: String in ["GroundShadow","RoomContactShadow"]:
		var shadow: CanvasItem = _actor.get_node_or_null(child_name) as CanvasItem
		if shadow != null:
			_shadows.append(shadow)
			_shadow_visibility.append(shadow.visible)
	_cover.show()
	_beam.show()
	_update_visuals()


func _process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	_update_visuals()
	var duration: float = arrival_duration if _arriving else departure_duration
	if elapsed >= duration:
		running = false
		_restore_actor()
		_beam.hide()
		if _arriving:
			_cover.hide()
		finished.emit(_arriving)


func _update_visuals() -> void:
	if not is_instance_valid(_actor):
		return
	var duration: float = maxf(arrival_duration if _arriving else departure_duration,0.05)
	var progress: float = clampf(elapsed/duration,0.0,1.0)
	var reveal: float = smoothstep(0.22,0.54,progress) if _arriving else 1.0-smoothstep(0.20,0.62,progress)
	var whiten: float = 1.0-smoothstep(0.36,0.72,progress) if _arriving else smoothstep(0.0,0.22,progress)
	var coverage: float = 1.0-smoothstep(0.0,0.20,progress) if _arriving else smoothstep(0.58,1.0,progress)
	_fade_material.set_shader_parameter("coverage",coverage)
	_character_material.set_shader_parameter("reveal",reveal)
	_character_material.set_shader_parameter("whiten",whiten)
	if is_instance_valid(_weapon):
		_weapon.modulate = Color(_weapon_color.r,_weapon_color.g,_weapon_color.b,_weapon_color.a*reveal)
	_beam.global_position = _actor.surface_world_position()+Vector2(0,7)
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var size: Vector2 = get_viewport().get_visible_rect().size
	var top: float = minf((inverse*Vector2.ZERO).y,(inverse*Vector2(size.x,0)).y)
	_beam.set("height",maxf(64.0,_beam.global_position.y-top+16.0))
	_beam.call("set_phase",progress,_arriving)
	for index: int in range(_shadows.size()):
		if is_instance_valid(_shadows[index]):
			_shadows[index].visible = _shadow_visibility[index] and reveal > 0.45


func _restore_actor() -> void:
	if is_instance_valid(_actor):
		_actor.body.material = _original_material
	if is_instance_valid(_weapon):
		_weapon.modulate = _weapon_color
	_weapon = null
	for index: int in range(_shadows.size()):
		if is_instance_valid(_shadows[index]):
			_shadows[index].visible = _shadow_visibility[index]
	_shadows.clear()
	_shadow_visibility.clear()


func _exit_tree() -> void:
	_restore_actor()
	if is_instance_valid(_beam):
		_beam.queue_free()
