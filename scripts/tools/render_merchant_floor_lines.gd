extends SceneTree

const FLOOR_GEOMETRY: Script = preload("res://scripts/merchant_floor_geometry.gd")
const OUTPUT_PATH: String = "res://renders/merchant_floor_lines_960x270.png"
const MARGIN_OUTPUT_PATH: String = "res://renders/merchant_floor_lines_1024x334.png"


func _init() -> void:
	_render.call_deferred()


func _render() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = FLOOR_GEOMETRY.ROOM_SIZE
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var drawing: Node2D = Node2D.new()
	drawing.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(drawing)
	_add_line(drawing, FLOOR_GEOMETRY.walkable_polygon(), true)
	for points: PackedVector2Array in FLOOR_GEOMETRY.stair_lines():
		_add_line(drawing, points, false)
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	var error: Error = image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Não foi possível salvar %s: %s" % [OUTPUT_PATH, error_string(error)])
		quit(1)
		return
	print("MERCHANT_FLOOR_RENDER_OK %dx%d" % [image.get_width(), image.get_height()])
	# Technical floor reference only; the gameplay scenery is now merchant_hall.png.
	viewport.size = FLOOR_GEOMETRY.RENDER_SIZE
	drawing.position = Vector2.ONE * float(FLOOR_GEOMETRY.CAMERA_MARGIN)
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	error = image.save_png(MARGIN_OUTPUT_PATH)
	if error != OK:
		push_error("Falha ao salvar render com margem: %s" % error_string(error))
		quit(1)
		return
	print("MERCHANT_MARGIN_RENDER_OK %dx%d" % [image.get_width(), image.get_height()])
	quit(0)


func _add_line(parent: Node2D, points: PackedVector2Array, closed: bool) -> void:
	var line: Line2D = Line2D.new()
	line.points = points
	line.closed = closed
	line.width = 1.0
	line.default_color = Color.WHITE
	line.antialiased = false
	parent.add_child(line)
