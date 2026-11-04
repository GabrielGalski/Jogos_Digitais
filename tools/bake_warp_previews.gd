extends SceneTree
## Render the same native materials into LDtk previews; source sprites remain unchanged.

const VISUAL: Script = preload("res://scripts/visual/warp_visual.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for central: bool in [false, true]:
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(192, 256) if central else Vector2i(96, 96)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var visual: Node2D = VISUAL.new() as Node2D
		visual.call("configure", central)
		visual.position = visual.get("source_center") as Vector2
		viewport.add_child(visual)
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var rendered: Image = viewport.get_texture().get_image()
		var path: String = "res://assets/tiles/structures/central_warp_preview.png" if central else "res://assets/tiles/structures/warp_preview.png"
		if rendered.save_png(path) != OK:
			push_error("Could not save " + path)
			quit(1)
			return
		viewport.queue_free()
		await process_frame
	print("WARP_PREVIEWS PASS")
	quit()
