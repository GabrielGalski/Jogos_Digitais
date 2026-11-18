extends SceneTree
## Crown projection, forest coverage, stable union, canonical cache,
## actual world geometry and rendered compositing. Use -- --capture.

const FIELD: Script = preload("res://scripts/visual/tree_shadow_field.gd")
const SHADOWS: Script = preload("res://scripts/visual/tree_shadows.gd")
const PROFILE: Resource = preload("res://resources/visual/terrain/tree_shadows.tres")
var failures: Array[String] = []
var arena: Node2D = null
var rendered: bool = false


func _initialize() -> void:
	rendered = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func caster(point: Vector2) -> Dictionary:
	return {"anchor": point, "crown": PackedVector2Array([
		Vector2(-28, -60), Vector2(12, -60), Vector2(12, -20), Vector2(-28, -20)]),
		"crown_center": Vector2(-8, -40), "contact_enabled": true,
		"crown_height": 48.0, "terrain_height": 0.0, "source_hash": "test_square",
		"scale": Vector2.ONE, "weight": 1.0}


func test_profile() -> Resource:
	var result: Resource = PROFILE.duplicate()
	result.set("projection_direction", Vector2.DOWN)
	result.set("projection_length", 60.0)
	result.set("crown_scale", Vector2.ONE)
	result.set("projection_compression", 0.55)
	result.set("contact_radius", Vector2(6, 3))
	result.set("forest_gap_px", 12.0)
	result.set("forest_max_link_distance", 96.0)
	result.set("forest_crown_scale", 1.0)
	return result


func sample(field: Dictionary, point: Vector2) -> float:
	var bounds: Rect2 = field.bounds as Rect2
	if not bounds.has_point(point): return 0.0
	return (field.image as Image).get_pixelv(Vector2i((point - bounds.position) / float(field.sample_size))).r


func _corrupted_cache_checks(casters: Array[Dictionary], profile: Resource, baseline: Dictionary) -> void:
	# This key belongs only to the isolated synthetic fixture, never map caches.
	var stem: String = "user://visual_cache/tree_shadows/" + str(baseline.key)
	for corruption: String in ["metadata_type", "old_version", "png_bytes"]:
		var path: String = stem + (".png" if corruption == "png_bytes" else ".json")
		var stream: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		check(stream != null, "Synthetic cache fixture can be written")
		if stream == null: return
		if corruption == "metadata_type":
			stream.store_string("[]")
		elif corruption == "old_version":
			stream.store_string(JSON.stringify({"version": -1}))
		else:
			stream.store_buffer(PackedByteArray([0, 1, 2, 3]))
		stream.close()
		var recovered: Dictionary = FIELD.build(casters, profile, true)
		check(not bool(recovered.cache_hit) and (recovered.image as Image).get_data() == (baseline.image as Image).get_data(), "Invalid " + corruption + " is safely rebuilt to the exact original mask")
	var repaired: Dictionary = FIELD.build(casters, profile, true)
	check(bool(repaired.cache_hit), "A repaired synthetic cache is reusable on its next load")


func _run() -> void:
	var profile: Resource = test_profile()
	var isolated: Dictionary = FIELD.build([caster(Vector2.ZERO)], profile, false)
	var hollow_crown: Dictionary = caster(Vector2.ZERO)
	hollow_crown.crown_center = Vector2.ZERO
	hollow_crown.crown = PackedVector2Array([Vector2(-30, -30), Vector2(30, -30),
		Vector2(30, -20), Vector2(-20, -20), Vector2(-20, 30), Vector2(-30, 30)])
	var rooted: Dictionary = FIELD.build([hollow_crown], profile, false)
	check(sample(rooted, Vector2.ZERO) > 0.98 and sample(rooted, Vector2(12, 0)) < 0.01, "A small root contact grounds the tree even where its irregular crown leaves the floor open")
	var trunk_only: Dictionary = caster(Vector2.ZERO)
	trunk_only.crown = PackedVector2Array()
	var root_only: Dictionary = FIELD.build([trunk_only], profile, false)
	check(not root_only.is_empty() and sample(root_only, Vector2.ZERO) > 0.98 and sample(root_only, Vector2(12, 0)) < 0.01, "A trunk-only selection keeps its small contact without inventing a complete crown")
	check(sample(isolated, Vector2(0, 60)) > 0.98 and sample(isolated, Vector2(0, -60)) < 0.01, "The crown projects toward the configured light direction")
	var right_profile: Resource = profile.duplicate()
	right_profile.set("projection_direction", Vector2.RIGHT)
	var right: Dictionary = FIELD.build([caster(Vector2.ZERO)], right_profile, false)
	check(sample(right, Vector2(60, 0)) > 0.98 and sample(right, Vector2(-60, 0)) < 0.01, "Rotating light direction moves the finite crown projection")
	var tall: Dictionary = caster(Vector2.ZERO)
	tall.crown_height = 96.0
	var taller: Dictionary = FIELD.build([tall], profile, false)
	check(sample(taller, Vector2(0, 120)) > 0.98 and sample(isolated, Vector2(0, 120)) < 0.01, "A taller crown casts a longer finite projection")
	var paired_casters: Array[Dictionary] = [caster(Vector2(-25, 0)), caster(Vector2(25, 0))]
	var paired: Dictionary = FIELD.build(paired_casters, profile, false)
	var small_gap: Vector2 = Vector2(0, -12)
	check(sample(paired, small_gap) > 0.98 and int(paired.get("forest_link_count", 0)) > 0, "Neighbouring crowns close a small forest gap")
	check(sample(isolated, Vector2.ZERO) == sample(paired, small_gap), "Forest overlap keeps exactly one solid intensity")
	var without_links: Resource = profile.duplicate()
	without_links.set("forest_gap_px", 0.0)
	var separated: Dictionary = FIELD.build(paired_casters, without_links, false)
	check(sample(separated, small_gap) < 0.01, "The forest connector fills a real small gap rather than a projection overlap")
	var upper_caster: Dictionary = caster(Vector2(25, 0))
	upper_caster.terrain_height = 24.0
	var height_partition: Dictionary = FIELD.build([caster(Vector2(-25, 0)), upper_caster], profile, false)
	check(sample(height_partition, small_gap) < 0.01 and int(height_partition.get("forest_link_count", 0)) == 0, "Trees on different elevation planes do not fill the intervening clearing")
	var distant: Dictionary = FIELD.build([caster(Vector2(-140, 0)), caster(Vector2(140, 0))], profile, false)
	check(sample(distant, Vector2.ZERO) < 0.01, "A wide clearing stays open")
	var triangle: Dictionary = caster(Vector2.ZERO)
	triangle.crown = PackedVector2Array([Vector2(-20, -20), Vector2(20, 20), Vector2(-20, 20)])
	triangle.crown_center = Vector2.ZERO
	triangle.source_hash = "partial_triangle"
	var clipped: Dictionary = FIELD.build([triangle], profile, false)
	check(sample(clipped, Vector2(-16, 4)) > 0.98 and sample(clipped, Vector2(16, -12)) < 0.01, "An incomplete crown retains its visible silhouette instead of expanding to an ellipse")
	var mirrored: Dictionary = triangle.duplicate(true)
	mirrored.crown = PackedVector2Array([Vector2(20, -20), Vector2(-20, 20), Vector2(20, 20)])
	var flipped: Dictionary = FIELD.build([mirrored], profile, false)
	check(sample(flipped, Vector2(16, 4)) > 0.98 and sample(flipped, Vector2(-16, -12)) < 0.01, "A mirrored source crown casts a mirrored coverage shape")
	var fragment: Dictionary = caster(Vector2.ZERO)
	fragment.crown_center = Vector2.ZERO
	fragment.contact_enabled = false
	fragment.crown = PackedVector2Array([Vector2(10, -20), Vector2(30, -20), Vector2(30, 20), Vector2(10, 20)])
	fragment.crowns = [fragment.crown]
	var partial: Dictionary = FIELD.build([fragment], profile, false)
	check(sample(partial, Vector2(20, 0)) > 0.98 and sample(partial, Vector2.ZERO) < 0.01, "A right-side crown fragment keeps the full crown centre and creates no invisible trunk contact")
	check(sample(partial, Vector2(20, 60)) > 0.98 and sample(partial, Vector2(0, 60)) < 0.01, "A partial crown projects in its original side rather than being recentered")
	var split: Dictionary = fragment.duplicate(true)
	split.crowns = [PackedVector2Array([Vector2(-30, -20), Vector2(-5, -20), Vector2(-5, 20), Vector2(-30, 20)]),
		PackedVector2Array([Vector2(5, -20), Vector2(30, -20), Vector2(30, 20), Vector2(5, 20)])]
	var erased_middle: Dictionary = FIELD.build([split], profile, false)
	check(sample(erased_middle, small_gap) < 0.01 and int(erased_middle.get("forest_link_count", 0)) == 0, "Disconnected fragments from one intentionally erased crown do not create forest stitches across the erased gap")
	var dense: Dictionary = FIELD.build([caster(Vector2.ZERO), caster(Vector2.ZERO), caster(Vector2.ZERO), caster(Vector2.ZERO)], profile, false)
	check(sample(dense, Vector2.ZERO) > 0.98, "Dense overlap reaches the shared cap")
	var shifted: Array[Dictionary] = [caster(Vector2(-456, -789))]
	var cached_once: Dictionary = FIELD.build(shifted, profile, true)
	var cached_twice: Dictionary = FIELD.build(shifted, profile, true)
	check(bool(cached_twice.cache_hit) and (cached_once.image as Image).get_data() == (cached_twice.image as Image).get_data(), "Disk cache retains the exact R8 density field")
	_corrupted_cache_checks(shifted, profile, cached_twice)
	check(sample(cached_twice, Vector2(-456, -789)) > 0.4, "Trees outside positive map coordinates retain their shadows")
	check(str(cached_once.key) != str(FIELD.build([caster(Vector2(-452, -789))], profile, false).key), "Moving a tree invalidates the cached field")
	var reordered: Array[Dictionary] = paired_casters.duplicate(true)
	reordered.reverse()
	check(str(paired.key) == str(FIELD.build(reordered, profile, false).key), "Tree enumeration order does not change the canonical cache key")
	var recoloured_profile: Resource = profile.duplicate()
	recoloured_profile.set("strength", 0.22)
	recoloured_profile.set("tint", Color("#29192c"))
	check(str(cached_once.key) == str(FIELD.build(shifted, recoloured_profile, false).key), "Tint and opacity change only the draw material and retain the geometry cache")
	for parameter: String in ["projection_direction", "projection_length", "projection_compression", "crown_scale", "forest_gap_px", "forest_max_link_distance", "forest_crown_scale", "contact_radius"]:
		var changed_profile: Resource = profile.duplicate()
		var previous: Variant = profile.get(parameter)
		if previous is Vector2:
			changed_profile.set(parameter, (previous as Vector2) + Vector2(0.25, 0.5))
		else:
			changed_profile.set(parameter, float(previous) + 1.0)
		check(str(cached_once.key) != str(FIELD.build(shifted, changed_profile, false).key), "Changing " + parameter + " invalidates the cached field")
	for parameter: String in ["source_hash", "crown_height", "terrain_height", "crown", "crown_center", "contact_enabled"]:
		var changed_caster: Dictionary = shifted[0].duplicate(true)
		if parameter == "source_hash": changed_caster.source_hash = "changed_source"
		elif parameter == "crown": changed_caster.crown = triangle.crown
		elif parameter == "crown_center": changed_caster.crown_center = Vector2.ZERO
		elif parameter == "contact_enabled": changed_caster.contact_enabled = false
		else: changed_caster[parameter] = float(changed_caster[parameter]) + 5.0
		check(str(cached_once.key) != str(FIELD.build([changed_caster], profile, false).key), "Changing caster " + parameter + " invalidates the cached field")
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	await create_timer(0.6).timeout
	var shadows: Node2D = arena.get_node("TreeShadows") as Node2D
	var actual: Dictionary = shadows.get("field") as Dictionary
	var tree_count: int = arena.get_node("Trees").get_child_count()
	check(int(actual.get("caster_count", 0)) == tree_count, "Every authored tree contributes once")
	check(not shadows.is_processing() and not shadows.is_physics_processing(), "Tree shadows have no per-frame updates")
	if tree_count == 0:
		check(actual.is_empty() and shadows.get_child_count() == 0, "A clean map allocates no tree-shadow texture or sprite")
	else:
		check(shadows.get_child_count() == 1 and (actual.image as Image).get_format() == Image.FORMAT_R8 and int(actual.bytes) < 4 * 1024 * 1024, "Painted trees share one bounded R8 mask")
	check(not bool(arena.call("is_ground_surface_point", Vector2(3500, 3300))), "Solid background does not create walkable floor outside the map")
	check((arena.get_node("Backdrop") as Polygon2D).color.is_equal_approx(Color("#533048")), "Backdrop matches the solid authored base")
	check(not arena.get_node("LdtkLayers").has_node("ForestBase_0"), "No hard forest band is drawn")
	var key_before: String = str(actual.get("key", ""))
	for index: int in range(8): await process_frame
	check(key_before == str((shadows.get("field") as Dictionary).get("key", "")), "Gameplay frames keep the same cached mask")
	var casters: Array[Dictionary] = arena.get_node("Trees").call("shadow_descriptions") as Array[Dictionary]
	var authored_trees: Array[Node] = arena.get_node("Trees").get_children()
	for index: int in range(casters.size()):
		var actual_caster: Dictionary = casters[index]
		check(actual_caster.has("anchor") and actual_caster.has("crown") and ((actual_caster.crown as PackedVector2Array).size() >= 3 or bool(actual_caster.get("contact_enabled", false))), "Actual tree supplies a root anchor with its visible crown or trunk contact")
		check(not str(actual_caster.get("source_hash", "")).is_empty(), "Actual tree cache identifies its current source silhouette")
		var tree: Node2D = authored_trees[index] as Node2D
		var expected_anchor: Vector2 = (tree.get_meta(&"footprint") as Rect2).get_center() - Vector2(0, float(tree.get_meta(&"projected_height")))
		check((actual_caster.anchor as Vector2).is_equal_approx(expected_anchor), "Each real tree shadow stays at its visible ground root, including elevated trees")
		check(bool(actual_caster.get("contact_enabled", true)) == tree.has_node("Trunk"), "Canopy-only selections do not acquire an invisible trunk shadow")
	var report: Dictionary = {"casters": tree_count, "mask_bytes": 0, "empty_map": tree_count == 0}
	if not casters.is_empty():
		var cold: Dictionary = FIELD.build(casters, PROFILE, false)
		var warm: Dictionary = FIELD.build(casters, PROFILE, true)
		check(str(cold.key) == str(actual.key) and (cold.image as Image).get_data() == (warm.image as Image).get_data(), "Actual map cache is identical to a fresh bake")
		report.merge({"mask_bytes": actual.bytes, "cold_build_ms": cold.build_ms,
			"warm_load_ms": warm.build_ms, "cache_hit": warm.cache_hit,
			"forest_links": actual.get("forest_link_count", 0), "polygons": actual.get("polygon_count", 0),
			"crown_vertices": actual.get("source_vertex_count", 0)}, true)
	DirAccess.make_dir_recursive_absolute("res://output/sombras_arvores")
	var stream: FileAccess = FileAccess.open("res://output/sombras_arvores/performance.json", FileAccess.WRITE)
	stream.store_string(JSON.stringify(report, "\t"))
	stream.close()
	print(JSON.stringify(report))
	if rendered: await _pixel_checks()
	print("TREE_SHADOWS_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)


func _frame(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


func _pixel_checks() -> void:
	var view: SubViewport = SubViewport.new()
	view.size = Vector2i(256, 192)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var background: Polygon2D = Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2.ZERO, Vector2(256, 0), Vector2(256, 192), Vector2(0, 192)])
	background.color = Color("#533048")
	background.z_index = -90
	view.add_child(background)
	var shadows: Node2D = SHADOWS.new() as Node2D
	view.add_child(shadows)
	shadows.call("configure", [caster(Vector2(104, 96)), caster(Vector2(152, 96))], test_profile(), false)
	var actor: Polygon2D = Polygon2D.new()
	actor.polygon = PackedVector2Array([Vector2(108, 146), Vector2(148, 146), Vector2(148, 176), Vector2(108, 176)])
	actor.color = Color("#bac9cd")
	actor.z_index = 2
	view.add_child(actor)
	var shaded: Image = await _frame(view)
	shadows.hide()
	var clean: Image = await _frame(view)
	check(shaded.get_pixel(128, 84).r < clean.get_pixel(128, 84).r * 0.96 and shaded.get_pixel(128, 84).r > clean.get_pixel(128, 84).r * 0.75, "Rendered shadow remains discreet at its solid low intensity")
	check(shaded.get_pixel(16, 16).is_equal_approx(clean.get_pixel(16, 16)), "Outside the shadow, the floor keeps its exact base colour")
	check(clean.get_pixel(16, 16).is_equal_approx(Color("#533048")), "The solid base renders as authored before lighting")
	check(shaded.get_pixel(110, 156).is_equal_approx(clean.get_pixel(110, 156)), "Actors above the projected shadow retain their colour")
	var floor_colours: Dictionary[int, bool] = {}
	for y: int in range(shaded.get_height()):
		for x: int in range(shaded.get_width()):
			if Rect2i(108, 146, 40, 30).has_point(Vector2i(x, y)): continue
			floor_colours[shaded.get_pixel(x, y).to_rgba32()] = true
	check(floor_colours.size() == 2, "Interpolated contours still render only one shadow tone and the original floor, without penumbra")
	shaded.save_png("res://output/sombras_arvores/composicao_teste.png")
	clean.save_png("res://output/sombras_arvores/composicao_sem_sombra.png")
