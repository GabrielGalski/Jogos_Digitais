extends "res://tools/castle_cliffs_regression.gd"
## Real map: preserve author edits, curved support/collision, bridges and rendering.


func _check_preservation() -> void:
	var migration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://output/curved_river/migration.json")) as Dictionary
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(migration.get("backup", "")))) as Dictionary
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_FILE)) as Dictionary
	var source_ids: Dictionary = {}
	for level: Dictionary in source.get("levels", []): source_ids[str(level.iid)] = level
	var barrier_count: int = 0
	for level: Dictionary in current.get("levels", []):
		var original: Dictionary = source_ids[str(level.iid)] as Dictionary
		for old_layer: Dictionary in original.layerInstances:
			check(_layer(level, str(old_layer.__identifier)) == old_layer, "Every prior tile, barrier, entity and IntGrid is preserved: " + str(level.identifier) + "/" + str(old_layer.__identifier))
		barrier_count += (_layer(level, "Barriers").get("gridTiles", []) as Array).size()
	check(barrier_count == 424, "All 424 newly authored barrier pieces remain placed")
	report["preserved_barrier_tiles"] = barrier_count


func _physics_checks() -> void:
	await super._physics_checks()
	_check_preservation()
	var adapter: Node2D = arena.get_node_or_null("RiverContour") as Node2D
	check(adapter != null and adapter.get("contour") != null, "Current map creates its functional river contour")
	if adapter == null or adapter.get("contour") == null: return
	var model: RefCounted = adapter.get("contour") as RefCounted
	check((model.get("diagnostics") as Array[String]).is_empty(), "Authored RiverMask is a continuous, valid channel")
	check(float(model.get("max_visible_shift")) <= 8.001, "Visible curves stay within 8 px of the authored edges")
	var profile: ImageTexture = model.get("profile_texture") as ImageTexture
	check(profile.get_width() == 1 and profile.get_image().get_data_size() < 32768, "Bank profile needs less than 32 KiB and is built once")
	var boundary: StaticBody2D = arena.get_node("FloorBoundary") as StaticBody2D
	check(boundary.has_node("RiverBanks"), "Curves supply a static physical shore")
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	var surface: Sprite2D = water.regions[0].get_node("Surface") as Sprite2D
	var water_material: ShaderMaterial = surface.material as ShaderMaterial
	check(water_material.get_shader_parameter(&"river_profile") == profile, "Surface and geometry share the same profile")
	check(is_equal_approx(float(water_material.get_shader_parameter(&"river_edge_softness_px")), 1.0), "Antialiasing is restricted to one native world pixel")
	check(bool(water_material.get_shader_parameter(&"combined_foam")) and float(water_material.get_shader_parameter(&"foam_opacity")) > 0.0, "Subtle moving foam is enabled on the curved coast")
	var cliff: TileMapLayer = arena.get_node("LdtkLayers/TerrainCliffRim_0") as TileMapLayer
	check((cliff.material as ShaderMaterial).get_shader_parameter(&"river_contour_enabled") != true, "The authored castle cliff retains its independent alpha and projection")
	var fractional: int = 0
	var rays: int = 0
	var mismatch: int = 0
	var mismatch_details: Array[Dictionary] = []
	var space: PhysicsDirectSpaceState2D = arena.get_world_2d().direct_space_state
	for y: int in range(129, 3200, 29):
		var banks: Vector4 = model.call("banks_at", float(y)) as Vector4
		for side: int in range(2):
			var active: float = banks.z if side == 0 else banks.w
			if active < 0.99: continue
			var x: float = banks.x if side == 0 else banks.y
			var bank: Vector2 = Vector2(x, y)
			if bool(model.call("in_bridge", bank)): continue
			if absf(x - roundf(x)) > 0.02: fractional += 1
			var inward: Vector2 = Vector2.RIGHT if side == 0 else Vector2.LEFT
			check(bool(arena.call("is_ground_surface_point", bank - inward * 2.0)), "The visible land side supplies ground at " + str(bank))
			check(not bool(arena.call("is_ground_surface_point", bank + inward * 2.0)), "The visible river side has no ground at " + str(bank))
			for reverse: bool in [false, true]:
				var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(bank - inward * 6.0, bank + inward * 6.0, 1)
				if reverse:
					query.from = bank + inward * 6.0
					query.to = bank - inward * 6.0
				var hit: Dictionary = space.intersect_ray(query)
				# User-painted barriers and tree bases retain priority if adjacent.
				if not hit.is_empty() and hit.get("collider") != boundary: continue
				rays += 1
				if hit.is_empty() or (hit.get("position", Vector2.INF) as Vector2).distance_to(bank) > 0.6:
					mismatch += 1
					mismatch_details.append({"bank": bank, "hit": hit.get("position"), "reverse": reverse})
	check(fractional > 40, "The coastline contains actual subcell curves rather than 16 px steps")
	check(rays > 200 and mismatch == 0, "Both directions of real ray contact match curved shore positions within 0.6 px")
	for deck: Rect2 in model.get("bridges") as Array[Rect2]:
		var start: Vector2 = Vector2(deck.position.x - 16.0, deck.get_center().y - 3.0)
		check(not player.test_move(Transform2D(0.0, start), Vector2(deck.size.x + 32.0, 0)), "The player's real shape crosses each preserved bridge without shore blockers")
	# A player-sized walk and fast dash both meet the new curved outline.
	var sample: Vector4 = model.call("banks_at", 1808.0) as Vector4
	var land_start: Vector2 = Vector2(sample.x - 24.0, 1808.0)
	check(player.test_move(Transform2D(0.0, land_start), Vector2(48, 0)), "Walking into the river is blocked")
	check(player.test_move(Transform2D(0.0, land_start), Vector2(400, 0)), "Dash sweep cannot tunnel through the curved shoreline")
	report["curve_ray_checks"] = rays
	report["curve_ray_mismatches"] = mismatch
	report["curve_ray_details"] = mismatch_details
	report["fractional_bank_samples"] = fractional
	report["bank_profile_bytes"] = profile.get_image().get_data_size()
	report["contour_build_ms"] = float(model.get("build_usec")) / 1000.0
	report["visible_max_shift_px"] = model.get("max_visible_shift")
	report["topology_patterns"] = (model.get("topology_counts") as Dictionary).size()
	report["reclaimed_ground_quads"] = adapter.get_node("GroundFill").get_meta(&"quad_count")
	DirAccess.make_dir_recursive_absolute("res://output/curved_river")
	var result: FileAccess = FileAccess.open("res://output/curved_river/physics_report.json", FileAccess.WRITE)
	result.store_string(JSON.stringify(report, "\t"))
	result.close()


func _save_view(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://output/curved_river/" + label + ".png") == OK, "Rendered river view: " + label)


func _render_views() -> void:
	if not rendered: return
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	water.set_process(false)
	water.set_elapsed(12.0)
	var views: Array[Dictionary] = [
		{"id": "01_cliff_preserved", "point": Vector2(2520, 1030), "zoom": 2.0},
		{"id": "02_upper_bridge", "point": Vector2(2680, 1440), "zoom": 1.9},
		{"id": "03_middle_bank", "point": Vector2(2550, 1760), "zoom": 2.2},
		{"id": "04_lower_bridge", "point": Vector2(2610, 2280), "zoom": 1.9},
		{"id": "05_lower_bend", "point": Vector2(2770, 2720), "zoom": 1.25},
	]
	for view: Dictionary in views:
		_place((view.point as Vector2) - Vector2(150, 0))
		await _frame(view.point as Vector2, float(view.zoom))
		await _save_view(str(view.id))
	root.content_scale_size = Vector2i(480, 320)
	root.size = Vector2i(1440, 960)
	_place(Vector2(2500, 1808))
	await _frame(Vector2(2560, 1808), 1.0)
	await _save_view("06_native_game_scale")
	water.set_elapsed(14.0)
	await _settle()
	await _save_view("07_motion_later")
	print("CURVED_RIVER_RENDERED " + str(failures.size()) + " failures")
