extends Node

const PIXELS_TO_WORLD: float = 0.01
const CAMERA_DISTANCE: float = 12.0
const PRESENTATION_LAYER: int = 10
const INDICATOR_LAYER: int = 45
const STATIC_2D_ROOTS: PackedStringArray = [
	"FarClouds",
	"NearClouds",
	"Floor",
	"PlatformUnderside",
	"EntranceStair",
	"LargeHoleEdge",
	"SmallHoleEdge",
	"ThronePath",
]

var _arena: Node2D = null
var _base_camera: Camera2D = null
var _profile: CameraViewProfile = null
var _active: bool = false
var _viewport: SubViewport = null
var _viewport_container: SubViewportContainer = null
var _world_root: Node3D = null
var _geometry_root: Node3D = null
var _proxy_root: Node3D = null
var _camera: Camera3D = null
var _environment: Environment = null
var _indicator_layer: CanvasLayer = null
var _indicator_label: Label = null
var _proxies: Dictionary = {}
var _shadows: Dictionary = {}


func configure(arena: Node2D, base_camera: Camera2D) -> void:
	_arena = arena
	_base_camera = base_camera
	_build_viewport()
	_build_indicator()
	set_process(false)


func activate(profile: CameraViewProfile) -> void:
	if _arena == null or _base_camera == null or _viewport == null:
		return
	_profile = profile
	_active = true
	_viewport_container.show()
	_indicator_layer.show()
	_indicator_label.text = "%s · %.0f°" % [profile.display_name, profile.elevation_degrees]
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_environment.background_color = profile.background_color
	_environment.ambient_light_color = profile.wall_top_color.lightened(0.16)
	_rebuild_geometry()
	_collect_visuals(_arena)
	_sync_visuals()
	_update_camera()
	set_process(true)


func deactivate() -> void:
	_active = false
	_profile = null
	set_process(false)
	if _viewport_container != null:
		_viewport_container.hide()
	if _indicator_layer != null:
		_indicator_layer.hide()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_proxies()


func is_active() -> bool:
	return _active


func screen_to_world(screen_position: Vector2) -> Vector2:
	if not _active or _camera == null or _arena == null:
		return Vector2.INF
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if intersection == null:
		return Vector2.INF
	var point: Vector3 = intersection as Vector3
	return _arena.to_global(Vector2(point.x, point.z) / PIXELS_TO_WORLD)


func visible_world_rect() -> Rect2:
	if not _active or _viewport == null:
		return Rect2()
	var screen_size: Vector2 = Vector2(_viewport.size)
	var corners: PackedVector2Array = PackedVector2Array([
		screen_to_world(Vector2.ZERO),
		screen_to_world(Vector2(screen_size.x, 0.0)),
		screen_to_world(screen_size),
		screen_to_world(Vector2(0.0, screen_size.y)),
	])
	var minimum: Vector2 = corners[0]
	var maximum: Vector2 = corners[0]
	for point: Vector2 in corners:
		if point == Vector2.INF:
			continue
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func _process(_delta: float) -> void:
	if not _active:
		return
	_collect_visuals(_arena)
	_sync_visuals()
	_update_camera()


func _build_viewport() -> void:
	var presentation_layer: CanvasLayer = CanvasLayer.new()
	presentation_layer.name = "SpatialPresentationLayer"
	presentation_layer.layer = PRESENTATION_LAYER
	add_child(presentation_layer)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "SpatialViewportContainer"
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	presentation_layer.add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.name = "SpatialViewport"
	_viewport.size = Vector2i(480, 270)
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport_container.add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "SpatialWorld"
	_viewport.add_child(_world_root)

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("25131a")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("d08b9d")
	_environment.ambient_light_energy = 0.86
	world_environment.environment = _environment
	_world_root.add_child(world_environment)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-52.0, -24.0, 0.0)
	light.light_color = Color("ffd0bc")
	light.light_energy = 0.72
	light.shadow_enabled = true
	_world_root.add_child(light)

	_geometry_root = Node3D.new()
	_geometry_root.name = "DungeonGeometry"
	_world_root.add_child(_geometry_root)

	_proxy_root = Node3D.new()
	_proxy_root.name = "BillboardProxies"
	_world_root.add_child(_proxy_root)

	_camera = Camera3D.new()
	_camera.name = "SpatialCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 40.0
	_camera.current = true
	_world_root.add_child(_camera)
	_viewport_container.hide()


func _build_indicator() -> void:
	_indicator_layer = CanvasLayer.new()
	_indicator_layer.name = "CameraModeIndicator"
	_indicator_layer.layer = INDICATOR_LAYER
	add_child(_indicator_layer)

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "ScreenMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	_indicator_layer.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.075, 0.035, 0.055, 0.9)
	panel_style.border_color = Color(0.68, 0.39, 0.47, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(2)
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_top = 4.0
	panel_style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", panel_style)
	row.add_child(panel)

	_indicator_label = Label.new()
	_indicator_label.name = "Mode"
	_indicator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator_label.add_theme_color_override("font_color", Color("f2c3c9"))
	_indicator_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_indicator_label.add_theme_constant_override("shadow_offset_x", 1)
	_indicator_label.add_theme_constant_override("shadow_offset_y", 1)
	_indicator_label.add_theme_font_size_override("font_size", 10)
	panel.add_child(_indicator_label)
	_indicator_layer.hide()


func _rebuild_geometry() -> void:
	for child: Node in _geometry_root.get_children():
		_geometry_root.remove_child(child)
		child.queue_free()

	var floor_material: StandardMaterial3D = _make_material(_profile.floor_color, false)
	var wall_material: StandardMaterial3D = _make_material(_profile.wall_color, false)
	var top_material: StandardMaterial3D = _make_material(_profile.wall_top_color, false)
	var grid_color: Color = _profile.wall_top_color.darkened(0.55)
	grid_color.a = 0.34
	var grid_material: StandardMaterial3D = _make_material(grid_color, true)
	var pit_material: StandardMaterial3D = _make_material(_profile.background_color.darkened(0.35), true)

	_add_box("ArenaFloor", Vector3(6.72, 0.08, 5.6), Vector3(0.0, -0.06, -0.4), floor_material)
	_add_box("EntranceFloor", Vector3(1.36, 0.08, 1.28), Vector3(0.0, -0.06, 3.0), floor_material)
	_add_floor_grid(grid_material)
	_add_plane("LargePit", Vector2(1.65, 1.28), Vector3(-1.76, 0.006, -0.8), pit_material)
	_add_plane("SmallPit", Vector2(0.96, 0.8), Vector3(1.38, 0.008, 0.08), pit_material)

	var height: float = _profile.wall_height
	var wall_y: float = height * 0.5
	_add_wall_with_cap("NorthWall", Vector3(6.96, height, 0.18), Vector3(0.0, wall_y, -3.23), wall_material, top_material)
	_add_wall_with_cap("WestWall", Vector3(0.18, height, 5.78), Vector3(-3.39, wall_y, -0.4), wall_material, top_material)
	_add_wall_with_cap("EastWall", Vector3(0.18, height, 5.78), Vector3(3.39, wall_y, -0.4), wall_material, top_material)
	_add_wall_with_cap("SouthWallLeft", Vector3(2.9, height, 0.18), Vector3(-1.95, wall_y, 2.43), wall_material, top_material)
	_add_wall_with_cap("SouthWallRight", Vector3(2.9, height, 0.18), Vector3(1.95, wall_y, 2.43), wall_material, top_material)
	_add_wall_with_cap("CorridorWest", Vector3(0.14, height, 1.38), Vector3(-0.68, wall_y, 3.0), wall_material, top_material)
	_add_wall_with_cap("CorridorEast", Vector3(0.14, height, 1.38), Vector3(0.68, wall_y, 3.0), wall_material, top_material)
	_add_wall_with_cap("NorthPillarLeft", Vector3(0.28, height * 1.2, 0.28), Vector3(-2.72, height * 0.6, -2.92), wall_material, top_material)
	_add_wall_with_cap("NorthPillarRight", Vector3(0.28, height * 1.2, 0.28), Vector3(2.72, height * 0.6, -2.92), wall_material, top_material)


func _add_floor_grid(material: StandardMaterial3D) -> void:
	for x_index: int in range(-10, 11):
		var x: float = float(x_index) * 0.32
		_add_box("GridX_%d" % x_index, Vector3(0.008, 0.004, 5.42), Vector3(x, 0.004, -0.4), material)
	for z_index: int in range(-9, 9):
		var z: float = float(z_index) * 0.32 - 0.4
		_add_box("GridZ_%d" % z_index, Vector3(6.54, 0.004, 0.008), Vector3(0.0, 0.005, z), material)


func _add_wall_with_cap(
	node_name: String,
	size: Vector3,
	position: Vector3,
	wall_material: StandardMaterial3D,
	top_material: StandardMaterial3D
) -> void:
	_add_box(node_name, size, position, wall_material)
	var cap_size: Vector3 = Vector3(size.x + 0.035, 0.035, size.z + 0.035)
	var cap_position: Vector3 = Vector3(position.x, size.y + 0.017, position.z)
	_add_box(node_name + "Cap", cap_size, cap_position, top_material)


func _add_box(node_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	_geometry_root.add_child(instance)


func _add_plane(node_name: String, size: Vector2, position: Vector3, material: Material) -> void:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	mesh.material = material
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	_geometry_root.add_child(instance)


func _make_material(color: Color, unshaded: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _collect_visuals(node: Node) -> void:
	for child: Node in node.get_children():
		if child == self or child is CanvasLayer or child is SubViewport or child is Node3D:
			continue
		if _is_static_2d_branch(child):
			continue
		if child is Sprite2D or child is AnimatedSprite2D:
			_ensure_proxy(child as CanvasItem)
		_collect_visuals(child)


func _is_static_2d_branch(node: Node) -> bool:
	return STATIC_2D_ROOTS.has(node.name)


func _ensure_proxy(source: CanvasItem) -> void:
	if _proxies.has(source):
		return
	var proxy: SpriteBase3D = null
	if source is AnimatedSprite2D:
		proxy = AnimatedSprite3D.new()
	else:
		proxy = Sprite3D.new()
	proxy.name = "Proxy_%s_%d" % [source.name, source.get_instance_id()]
	proxy.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	proxy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	proxy.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	proxy.shaded = false
	proxy.pixel_size = PIXELS_TO_WORLD
	proxy.centered = true
	_proxy_root.add_child(proxy)
	_proxies[source] = proxy

	var anchor: Node2D = _find_ground_anchor(source)
	if anchor is CharacterBody2D:
		_ensure_shadow(anchor)


func _ensure_shadow(anchor: Node2D) -> void:
	if _shadows.has(anchor):
		return
	var shadow_color: Color = Color(0.04, 0.015, 0.025, 0.48)
	var shadow_material: StandardMaterial3D = _make_material(shadow_color, true)
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.12
	mesh.height = 0.004
	mesh.radial_segments = 24
	mesh.material = shadow_material
	var shadow: MeshInstance3D = MeshInstance3D.new()
	shadow.name = "Shadow_%d" % anchor.get_instance_id()
	shadow.mesh = mesh
	shadow.scale = Vector3(1.0, 1.0, 0.46)
	_proxy_root.add_child(shadow)
	_shadows[anchor] = shadow


func _sync_visuals() -> void:
	var stale_sources: Array[CanvasItem] = []
	for key: Variant in _proxies.keys():
		var source: CanvasItem = key as CanvasItem
		if source == null or not is_instance_valid(source):
			stale_sources.append(source)
			continue
		var proxy: SpriteBase3D = _proxies.get(source) as SpriteBase3D
		if proxy == null or not is_instance_valid(proxy):
			stale_sources.append(source)
			continue
		_sync_proxy(source, proxy)
	for source: CanvasItem in stale_sources:
		var stale_proxy: Node = _proxies.get(source) as Node
		if stale_proxy != null and is_instance_valid(stale_proxy):
			stale_proxy.queue_free()
		_proxies.erase(source)

	var stale_anchors: Array[Node2D] = []
	for key: Variant in _shadows.keys():
		var anchor: Node2D = key as Node2D
		if anchor == null or not is_instance_valid(anchor):
			stale_anchors.append(anchor)
			continue
		var shadow: MeshInstance3D = _shadows.get(anchor) as MeshInstance3D
		if shadow == null or not is_instance_valid(shadow):
			stale_anchors.append(anchor)
			continue
		var local_position: Vector2 = _arena.to_local(anchor.global_position)
		shadow.position = Vector3(local_position.x * PIXELS_TO_WORLD, 0.012, local_position.y * PIXELS_TO_WORLD)
		shadow.visible = anchor.is_visible_in_tree()
	for anchor: Node2D in stale_anchors:
		var stale_shadow: Node = _shadows.get(anchor) as Node
		if stale_shadow != null and is_instance_valid(stale_shadow):
			stale_shadow.queue_free()
		_shadows.erase(anchor)


func _sync_proxy(source: CanvasItem, proxy: SpriteBase3D) -> void:
	if source is AnimatedSprite2D and proxy is AnimatedSprite3D:
		_sync_animated_sprite(source as AnimatedSprite2D, proxy as AnimatedSprite3D)
	elif source is Sprite2D and proxy is Sprite3D:
		_sync_sprite(source as Sprite2D, proxy as Sprite3D)

	var source_node: Node2D = source as Node2D
	var anchor: Node2D = _find_ground_anchor(source)
	var local_source: Vector2 = _arena.to_local(source_node.global_position)
	var local_anchor: Vector2 = _arena.to_local(anchor.global_position)
	var rect: Rect2 = _source_rect(source)
	var source_scale: Vector2 = source_node.global_scale
	var half_height: float = rect.size.y * absf(source_scale.y) * 0.5 * PIXELS_TO_WORLD
	var vertical_offset: float = (local_anchor.y - local_source.y) * PIXELS_TO_WORLD
	proxy.position = Vector3(
		local_source.x * PIXELS_TO_WORLD,
		maxf(half_height + vertical_offset, 0.006) + float(source.z_index) * 0.0004,
		local_anchor.y * PIXELS_TO_WORLD
	)
	proxy.scale = Vector3(absf(source_scale.x), absf(source_scale.y), 1.0)
	proxy.rotation.z = -source_node.global_rotation
	proxy.visible = source.is_visible_in_tree()
	proxy.modulate = _combined_modulate(source)


func _sync_animated_sprite(source: AnimatedSprite2D, proxy: AnimatedSprite3D) -> void:
	proxy.sprite_frames = source.sprite_frames
	proxy.animation = source.animation
	proxy.set_frame_and_progress(source.frame, source.frame_progress)
	proxy.flip_h = source.flip_h != (source.global_scale.x < 0.0)
	proxy.flip_v = source.flip_v != (source.global_scale.y < 0.0)


func _sync_sprite(source: Sprite2D, proxy: Sprite3D) -> void:
	proxy.texture = source.texture
	proxy.region_enabled = source.region_enabled
	proxy.region_rect = source.region_rect
	proxy.hframes = source.hframes
	proxy.vframes = source.vframes
	proxy.frame = source.frame
	proxy.flip_h = source.flip_h != (source.global_scale.x < 0.0)
	proxy.flip_v = source.flip_v != (source.global_scale.y < 0.0)


func _source_rect(source: CanvasItem) -> Rect2:
	if source is AnimatedSprite2D:
		var animated: AnimatedSprite2D = source as AnimatedSprite2D
		if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return Rect2()
		var texture: Texture2D = animated.sprite_frames.get_frame_texture(animated.animation, animated.frame)
		if texture == null:
			return Rect2()
		var size: Vector2 = texture.get_size()
		var rect_position: Vector2 = animated.offset
		if animated.centered:
			rect_position -= size * 0.5
		return Rect2(rect_position, size)
	if source is Sprite2D:
		return (source as Sprite2D).get_rect()
	return Rect2()


func _combined_modulate(source: CanvasItem) -> Color:
	var combined: Color = source.modulate * source.self_modulate
	var ancestor: Node = source.get_parent()
	while ancestor is CanvasItem and ancestor != _arena:
		var canvas_ancestor: CanvasItem = ancestor as CanvasItem
		combined *= canvas_ancestor.modulate
		combined *= canvas_ancestor.self_modulate
		ancestor = ancestor.get_parent()
	return combined


func _find_ground_anchor(source: CanvasItem) -> Node2D:
	var candidate: Node = source
	var last_node_2d: Node2D = source as Node2D
	while candidate != null and candidate != _arena:
		var candidate_2d: Node2D = candidate as Node2D
		if candidate_2d != null:
			last_node_2d = candidate_2d
			if candidate_2d.top_level or candidate_2d is CharacterBody2D or candidate_2d is Area2D or candidate_2d is StaticBody2D:
				return candidate_2d
			if candidate_2d.get_parent() == _arena:
				return candidate_2d
		candidate = candidate.get_parent()
	return last_node_2d


func _update_camera() -> void:
	if _profile == null:
		return
	var focus_global: Vector2 = _base_camera.get_screen_center_position() + _base_camera.offset
	var focus_2d: Vector2 = _arena.to_local(focus_global)
	var focus: Vector3 = Vector3(
		focus_2d.x * PIXELS_TO_WORLD,
		0.0,
		focus_2d.y * PIXELS_TO_WORLD + _profile.focus_depth_offset
	)
	var elevation: float = deg_to_rad(_profile.elevation_degrees)
	var camera_offset: Vector3 = Vector3(
		0.0,
		sin(elevation) * CAMERA_DISTANCE,
		cos(elevation) * CAMERA_DISTANCE
	)
	_camera.size = _profile.orthographic_size
	_camera.position = focus + camera_offset
	_camera.look_at(focus, Vector3.UP)
	_camera.rotate_object_local(Vector3.BACK, -_base_camera.rotation)


func _clear_proxies() -> void:
	for child: Node in _proxy_root.get_children():
		_proxy_root.remove_child(child)
		child.queue_free()
	_proxies.clear()
	_shadows.clear()
