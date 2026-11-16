extends Node2D
## One authored frame, mapped rune inlays and local six-altar progress; no travel route.

signal progress_changed(completed: int, active_runes: int, charged: bool)

const SOURCE: Texture2D = preload("res://assets/tiles/structures/final portal/portal1.png")
const MASK: Texture2D = preload("res://assets/visual/structures/final_portal_map.png")
const STONE: Shader = preload("res://shaders/castle_structure_palette.gdshader")
const RUNES: Shader = preload("res://shaders/final_portal_runes.gdshader")
const STATIC: Shader = preload("res://shaders/final_portal_static.gdshader")
const ENTITIES: Script = preload("res://scripts/dungeon/ldtk_door_blocks.gd")
const REQUIRED_ALTARS: int = 6
const RUNES_PER_ALTAR: int = 4
const SOURCE_PIVOT: Vector2 = Vector2(96, 104)

var completed_altars: int = 0
var active_runes: int = 0
var ready_for_final_battle: bool = false
var ground_height: float = 0.0
var _world: Node2D = null
var _tracked: Dictionary[String, Node2D] = {}
var _completed: Dictionary[String, bool] = {}
var _rune_material: ShaderMaterial = null
var _static_material: ShaderMaterial = null
var _static_sprite: Sprite2D = null
var _elapsed: float = 0.0
var _frame: int = -1


func _ready() -> void:
	set_physics_process(ready_for_final_battle)


func configure(world: Node2D, layers: Array, encounters: Array) -> void:
	_world = world
	position = castle_position(layers)
	ground_height = float(world.call("_terrain_and_warp_height", world.to_global(position)))
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group(&"final_portals")
	var presentation: Node2D = Node2D.new()
	presentation.name = "Presentation"
	presentation.position.y = -ground_height
	add_child(presentation)
	var body: Sprite2D = _sprite("Stone", SOURCE, presentation)
	var stone_material: ShaderMaterial = ShaderMaterial.new()
	stone_material.shader = STONE
	body.material = stone_material
	_static_sprite = _sprite("WhiteStatic", MASK, presentation)
	_static_material = ShaderMaterial.new()
	_static_material.shader = STATIC
	_static_sprite.material = _static_material
	var inscriptions: Sprite2D = _sprite("Runes", MASK, presentation)
	_rune_material = ShaderMaterial.new()
	_rune_material.shader = RUNES
	_rune_material.set_shader_parameter(&"rune_map", MASK)
	_rune_material.set_shader_parameter(&"idle_color", Color("#3e3546"))
	inscriptions.material = _rune_material
	for encounter: Node2D in encounters:
		var id: String = str(encounter.get("encounter_id"))
		if id.is_empty() or _tracked.has(id):
			continue
		_tracked[id] = encounter
		encounter.connect("cleared", _on_altar_cleared.bind(id))
		if int(encounter.get("phase")) == 2:
			_completed[id] = true
	_refresh_progress()


static func castle_position(layers: Array) -> Vector2:
	var castle: Rect2 = Rect2()
	for layer: Dictionary in layers:
		if not bool(layer.get("visible", true)):
			continue
		var offset: Vector2 = Vector2(float(layer.get("__pxTotalOffsetX", 0)), float(layer.get("__pxTotalOffsetY", 0)))
		for entity: Dictionary in layer.get("entityInstances", []):
			if str(entity.get("__identifier", "")) != "ElevationArea" or not bool(ENTITIES.fields(entity).get("Enabled", true)):
				continue
			var area: Rect2 = ENTITIES.entity_rect(entity, offset)
			if area.get_area() > castle.get_area():
				castle = area
	return Vector2(castle.get_center().x, castle.position.y + 288.0)


func _sprite(label: String, texture: Texture2D, parent: Node2D) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = label
	sprite.texture = texture
	sprite.centered = false
	sprite.position = -SOURCE_PIVOT
	parent.add_child(sprite)
	return sprite


func _on_altar_cleared(id: String) -> void:
	if not _tracked.has(id) or _completed.has(id):
		return
	_completed[id] = true
	_refresh_progress()


func _refresh_progress() -> void:
	completed_altars = mini(_completed.size(), REQUIRED_ALTARS)
	active_runes = completed_altars * RUNES_PER_ALTAR
	ready_for_final_battle = _tracked.size() == REQUIRED_ALTARS and completed_altars == REQUIRED_ALTARS
	_rune_material.set_shader_parameter(&"active_runes", active_runes)
	_static_sprite.visible = ready_for_final_battle
	set_physics_process(ready_for_final_battle)
	var gameplay: Node = _world.get_node("Gameplay")
	gameplay.call("set_condition", "all_six_altars_clear", ready_for_final_battle)
	progress_changed.emit(completed_altars, active_runes, ready_for_final_battle)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var frame: int = floori(_elapsed * 12.0)
	if frame != _frame:
		_frame = frame
		_static_material.set_shader_parameter(&"elapsed", _elapsed)
