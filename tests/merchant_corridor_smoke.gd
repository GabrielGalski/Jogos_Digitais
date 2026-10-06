extends SceneTree

const CORRIDOR: PackedScene = preload("res://scenes/merchant_corridor.tscn")
const FLOOR_GEOMETRY: Script = preload("res://scripts/merchant_floor_geometry.gd")
var failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var corridor: Node2D = CORRIDOR.instantiate() as Node2D
	root.add_child(corridor)
	# Keep hardware cursor movement from changing deterministic camera assertions.
	corridor.set_process_input(false)
	await create_timer(2.2).timeout
	var nox: Node2D = corridor.get_node("Nox") as Node2D
	var door: Node2D = corridor.get_node("World/Entrance/DoorPanel") as Node2D
	var fade: ColorRect = corridor.get_node("FadeLayer/Fade") as ColorRect
	var camera: Camera2D = corridor.get_node("RoomCamera") as Camera2D
	var hall: Sprite2D = corridor.get_node("World/MerchantHall") as Sprite2D
	var merchant: Area2D = corridor.get_node("World/Merchant") as Area2D
	var merchant_visual: AnimatedSprite2D = merchant.get_node("Visual") as AnimatedSprite2D
	var merchant_interaction: CollisionShape2D = merchant.get_node("InteractionArea") as CollisionShape2D
	var nox_visual: AnimatedSprite2D = nox.get_node("Visual") as AnimatedSprite2D
	_check(hall.texture.resource_path == "res://assets/merchant/merchant_hall.png", "Arte merchant_hall não aplicada")
	_check(hall.texture.get_size() == Vector2(1024, 334), "Dimensões incorretas da arte")
	_check(hall.position == Vector2(-32, -32) and hall.scale == Vector2.ONE and not hall.centered, "Arte desalinhada com piso/margem")
	_check(hall.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Filtro não preserva pixel art")
	_check(is_equal_approx(float(corridor.get("movement_speed")), 90.0), "Velocidade de Nox não aumentou 25%")
	_check(nox_visual.scale.is_equal_approx(Vector2(2.7, 2.7)), "Sprite de Nox não diminuiu 10%")
	_check(nox_visual.position.is_equal_approx(Vector2(0.0, -21.6)), "Âncora dos pés de Nox mudou após reescala")
	_check(merchant.is_in_group("interactable"), "Mercadora não está marcada como interagível")
	_check(merchant.position.is_equal_approx(Vector2(331.0, 103.0)), "Mercadora fora da posição do balcão")
	_check(merchant_visual.animation == &"idle" and merchant_visual.is_playing(), "Idle da mercadora não iniciou")
	_check(merchant_visual.sprite_frames.get_frame_count(&"idle") == 5, "Idle da mercadora não usa cinco quadros")
	for frame_index: int in range(5):
		var frame_texture: Texture2D = merchant_visual.sprite_frames.get_frame_texture(&"idle", frame_index)
		_check(frame_texture.resource_path == "res://assets/merchant/character/merchant_idle%d.png" % (frame_index + 1),
			"Quadro idle da mercadora fora de ordem")
		_check(frame_texture.get_size() == Vector2(512, 512), "Quadro idle desalinhado com a âncora da mercadora")
	_check(merchant_visual.scale.is_equal_approx(Vector2(0.11, 0.11)), "Escala incorreta da mercadora")
	_check(merchant_visual.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Filtro da mercadora não preserva pixel art")
	_check(merchant_interaction.shape is RectangleShape2D and not merchant_interaction.disabled, "Área interagível da mercadora não está pronta")
	var interactions: Array = merchant.get_meta("interactions", []) as Array
	_check(interactions.is_empty(), "Mercadora recebeu interações antes de serem definidas")
	var stair_lines: Array[Node] = corridor.find_children("Riser*", "Line2D", true, false)
	var expected_stair_lines: Array[PackedVector2Array] = FLOOR_GEOMETRY.stair_lines()
	_check(stair_lines.size() == 6, "Escada não possui as seis diagonais que delimitam os degraus")
	for stair_index: int in range(mini(stair_lines.size(), expected_stair_lines.size())):
		var stair_line_node: Node = stair_lines[stair_index]
		var stair_line: Line2D = stair_line_node as Line2D
		_check(stair_line != null and stair_line.points == expected_stair_lines[stair_index], "Diagonal da escada fora da projeção correta")
		_check(not is_equal_approx(stair_line.points[0].y, stair_line.points[1].y), "Linha horizontal permaneceu na escada")
		_check(stair_line.default_color == Color("25131a") and is_equal_approx(stair_line.width, 2.0), "Linha da escada fora do padrão #25131A")
	_check(corridor.find_children("*", "Polygon2D", true, false).is_empty(), "Preenchimento hard coded ainda presente")
	_check(corridor.get("state") == 2, "Entrada não concluída")
	_check(nox.position.distance_to(Vector2(60.0, 144.0)) < 1.0, "Parada fora do patamar")
	_check(door.visible, "Porta aberta após entrada")
	_check(corridor.get("floor_height") == 36.0, "Patamar sem altura 36")
	_check(camera.position == Vector2(240, 135), "Câmera não inicia na primeira tela")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://renders/merchant_hall_gameplay.png")
	# Real held input crosses both intermediate levels and reaches the corridor.
	_key(KEY_D, true)
	var seen_levels: Array[int] = []
	for frame_index: int in range(130):
		await physics_frame
		var level: int = int(corridor.get("floor_level"))
		if not seen_levels.has(level):
			seen_levels.append(level)
	_key(KEY_D, false)
	await create_timer(0.15).timeout
	_check(seen_levels.has(2) and seen_levels.has(1) and seen_levels.has(0), "Descida não atravessou os três níveis")
	_check(absf(nox.position.y - 180.0) < 0.1, "Pés não chegaram ao corredor y=180")
	# Clamps prevent crossing front/back borders; returning over the stairs restores height.
	for tick: int in range(100):
		corridor.call(&"_move_on_floor", Vector2.DOWN, 1.0 / 60.0)
	var ground: Vector2 = corridor.get("ground_position")
	_check(is_equal_approx(ground.y, 52.0), "Borda frontal não contém os pés")
	for tick: int in range(100):
		corridor.call(&"_move_on_floor", Vector2.UP, 1.0 / 60.0)
	ground = corridor.get("ground_position")
	_check(is_equal_approx(ground.y, 4.0), "Borda de fundo não contém os pés")
	for tick: int in range(250):
		corridor.call(&"_move_on_floor", Vector2.LEFT, 1.0 / 60.0)
	await create_timer(0.4).timeout
	_check(corridor.get("floor_height") == 36.0, "Subida não retornou ao patamar")
	_check(is_equal_approx(nox.position.x, 20.0), "Entrada fechada não bloqueia retorno")
	corridor.set("ground_position", Vector2(468.0, 28.0))
	_key(KEY_D, true)
	await create_timer(1.1).timeout
	_key(KEY_D, false)
	_check(corridor.get("state") == 2 and fade.color.a < 0.01, "Limite antigo ainda reinicia a sala")
	_check(nox.position.x > 480.0 and camera.position.x > 480.0, "Câmera não acompanha a continuação")
	_check(absf(camera.position.y - 127.0) < 0.1, "Movimento de Nox não eleva o enquadramento")
	_check(is_zero_approx(camera.rotation), "Câmera apresenta rotação lateral")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://renders/merchant_camera_continuation.png")
	_key(KEY_A, true)
	await create_timer(0.5).timeout
	_key(KEY_A, false)
	_check(camera.position.x < 536.0, "Câmera não acompanha o retorno")
	corridor.set("ground_position", Vector2(882.0, 28.0))
	_key(KEY_D, true)
	await create_timer(0.8).timeout
	_key(KEY_D, false)
	_check(corridor.get("state") == 3, "Saída não iniciou o reinício")
	_check(nox.position.x >= 912.0 and nox.position.x < 960.0, "Fade não começou perto da saída")
	_check(absf(camera.position.x - 720.0) < 2.0, "Câmera ultrapassa a borda final")
	await create_timer(3.2).timeout
	_check(corridor.get("state") == 2, "Reinício incompleto")
	_check(nox.position.distance_to(Vector2(60.0, 144.0)) < 1.0, "Nox não reapareceu no patamar")
	_check(fade.color.a < 0.01 and corridor.get("displayed_height") == 36.0, "Fade/altura não restaurados")
	_check(camera.position == Vector2(240, 135), "Câmera não voltou à entrada")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(root.get_visible_rect().size.x * 0.5, 0.0)
	corridor.call(&"_input", motion)
	await create_timer(0.7).timeout
	_check(camera.position.y < 125.0 and camera.position.y >= 122.9, "Mouse no topo não desloca a câmera")
	_check(nox.position.distance_to(Vector2(60, 144)) < 0.1, "Mouse moveu Nox")
	_check(is_zero_approx(camera.rotation), "Mouse provocou rotação lateral")
	_check(absf(camera.position.x - 240.0) < 0.1, "Mouse deslocou a câmera horizontalmente")
	_check_visible_margin()
	# Top cursor + movement toward the back is the maximum upward offset.
	_key(KEY_W, true)
	await create_timer(0.3).timeout
	_check(camera.position.y < 118.0, "Movimento e mouse não combinam o deslocamento superior")
	_check_visible_margin()
	_key(KEY_W, false)
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://renders/merchant_camera_look_up.png")
	motion.position = root.get_visible_rect().size
	corridor.call(&"_input", motion)
	await create_timer(0.8).timeout
	_check(camera.position.y > 131.0, "Mouse na parte inferior não neutraliza o olhar superior")
	if failures == 0:
		print("MERCHANT_CORRIDOR_SMOKE_OK: entrada, níveis, bordas, continuação, enquadramento superior, mouse, margem, saída e reinício")
	quit(0 if failures == 0 else 1)


func _check_visible_margin() -> void:
	# All visible corners must fit inside the render's 32 px overscan.
	var inverse: Transform2D = root.get_canvas_transform().affine_inverse()
	var viewport_size: Vector2 = root.get_visible_rect().size
	for corner: Vector2 in [Vector2.ZERO, Vector2(viewport_size.x, 0), viewport_size, Vector2(0, viewport_size.y)]:
		var world_corner: Vector2 = inverse * corner
		_check(Rect2(-32, -32, 1024, 334).has_point(world_corner), "Câmera revela área fora da margem do render")


func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
