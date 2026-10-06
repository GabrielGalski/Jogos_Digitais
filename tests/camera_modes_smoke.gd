extends SceneTree

const EXPECTED_ELEVATIONS: Array[float] = [70.0, 62.0, 55.0]

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	current_scene = main

	var arena: Node2D = main.get_node("TutorialArena") as Node2D
	var controller: CameraVisualizationController = arena.get_node("CameraVisualizationController") as CameraVisualizationController
	var base_camera: Camera2D = arena.get_node("Mox/Camera2D") as Camera2D
	var shooter: Node = arena.get_node("Mox/BoosterShooter")
	var boss: Node = arena.get_node("MinotaurChair")
	var horde: Node = arena.get_node("MinotaurChair/TutorialEncounter/Horde")
	await arena.entrance_finished
	var base_position: Vector2 = base_camera.position
	var base_zoom: Vector2 = base_camera.zoom

	_check(not controller.is_spatial_view_active(), "a partida começa na apresentação 2D original")
	for index: int in range(EXPECTED_ELEVATIONS.size()):
		await _tap_enter()
		_check(controller.is_spatial_view_active(), "Enter ativa a apresentação espacial %d" % index)
		var presenter: Node = controller.get_node("CameraSpatialPresenter")
		var spatial_camera: Camera3D = presenter.get_node("SpatialPresentationLayer/SpatialViewportContainer/SpatialViewport/SpatialWorld/SpatialCamera") as Camera3D
		var geometry: Node3D = presenter.get_node("SpatialPresentationLayer/SpatialViewportContainer/SpatialViewport/SpatialWorld/DungeonGeometry") as Node3D
		var proxies: Node3D = presenter.get_node("SpatialPresentationLayer/SpatialViewportContainer/SpatialViewport/SpatialWorld/BillboardProxies") as Node3D
		var active_profile: CameraViewProfile = controller.get("_active_profile") as CameraViewProfile
		_check(active_profile != null, "o perfil espacial está instanciado")
		_check(is_equal_approx(active_profile.elevation_degrees, EXPECTED_ELEVATIONS[index]), "a elevação do modo %d é real e correta" % index)
		_check(spatial_camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "os modos usam projeção ortográfica")
		_check(is_equal_approx(spatial_camera.size, 2.25), "o tamanho ortográfico permanece constante entre modos")
		_check(geometry.get_child_count() > 50, "a dungeon possui piso, grade, paredes, corredor e pilares")
		_check(proxies.get_child_count() > 0, "os sprites 2D foram espelhados como billboards")
		var visible_rect: Rect2 = controller.visible_world_rect()
		_check(visible_rect.size.x > 1.0 and visible_rect.size.y > 1.0, "a consulta de visibilidade espacial retorna uma área útil")
		var center_world: Vector2 = controller.screen_to_world(Vector2(240.0, 135.0))
		_check(center_world != Vector2.INF, "a tela espacial pode ser convertida de volta ao piso lógico")
		var shooter_mouse: Vector2 = shooter.call(&"_mouse_world_position") as Vector2
		var expected_mouse: Vector2 = controller.screen_to_world(root.get_mouse_position())
		_check(shooter_mouse.is_equal_approx(expected_mouse), "a mira consulta a projeção espacial ativa")
		var horde_rect: Rect2 = horde.call(&"visible_world_rect") as Rect2
		var boss_rect: Rect2 = boss.call(&"_visible_world_rect") as Rect2
		_check(horde_rect.is_equal_approx(visible_rect), "o spawner consulta a área visível espacial")
		_check(boss_rect.is_equal_approx(visible_rect), "Asterion consulta a área visível espacial")
		await _capture_mode(index)

	await _tap_enter()
	_check(not controller.is_spatial_view_active(), "o quarto Enter retorna à base 2D")
	_check(base_camera.position.is_equal_approx(base_position), "a posição da Camera2D base permanece intacta")
	_check(base_camera.zoom.is_equal_approx(base_zoom), "o zoom da Camera2D base permanece intacto")
	if _failures == 0:
		print("CAMERA_MODES_SMOKE_OK")
	quit(1 if _failures > 0 else 0)


func _tap_enter() -> void:
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_ENTER
	press.keycode = KEY_ENTER
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame
	var release: InputEventKey = InputEventKey.new()
	release.physical_keycode = KEY_ENTER
	release.keycode = KEY_ENTER
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame


func _capture_mode(index: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/camera_mode_%d.png" % (index + 1))


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[CAMERA MODES] " + message)
