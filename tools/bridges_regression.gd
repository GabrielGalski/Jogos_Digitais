extends "res://tools/room_2_regression.gd"
## Complete LDtk stamps, real deck traversal and visual-only submerged supports.

const BRIDGES: Script = preload("res://scripts/dungeon/ldtk_bridges.gd")

var bridge_geometry: Node2D = null
var wet_mask_samples: int = 0
var dry_mask_samples: int = 0


func _check_atlas(map_data: Dictionary, layers: Array) -> void:
	var definitions: Dictionary = map_data.get("defs", {}) as Dictionary
	var atlas_id: int = -1
	for definition: Dictionary in definitions.get("tilesets", []):
		if str(definition.get("relPath", "")).replace("\\", "/").ends_with("/bridge_all.png"):
			atlas_id = int(definition.uid)
			check(int(definition.get("tileGridSize", 0)) == 16, "Bridge atlas uses the map's 16 px grid")
	check(atlas_id >= 0, "Original bridge_all atlas is registered in LDtk")
	for layer_name: String in ["Floor_Bridges", "Bridge_BackRail", "Bridge_FrontRail", "Bridge_Facade"]:
		var found: bool = false
		for layer: Dictionary in layers:
			if str(layer.get("__identifier", "")) == layer_name:
				found = true
				check(int(layer.get("__tilesetDefUid", -1)) == atlas_id and not (layer.get("gridTiles", []) as Array).is_empty(), layer_name + " uses the authored bridge atlas")
		check(found, "Bridge authoring layer exists: " + layer_name)


func _check_approaches(layers: Array, decks: Array[Rect2]) -> void:
	check(not layers.is_empty(), "Composed bridge layers remain available")
	for index: int in range(decks.size()):
		var deck: Rect2 = decks[index]
		var label: String = "Bridge " + str(index + 1)
		for row: int in range(roundi(deck.size.y / 16.0)):
			var y: float = deck.position.y + float(row * 16) + 8.0
			check(bool(arena.call("is_ground_surface_point", Vector2(deck.position.x - 8.0, y))), label + " joins west-bank support along deck row " + str(row + 1))
			check(bool(arena.call("is_ground_surface_point", Vector2(deck.end.x + 8.0, y))), label + " joins east-bank support along deck row " + str(row + 1))
			var start: Vector2 = Vector2(deck.position.x - 16.0, y - 3.0)
			check(not player.test_move(Transform2D(0.0, start), Vector2(deck.size.x + 32.0, 0)), label + " has an unobstructed crossing along approach row " + str(row + 1))


func capture(label: String) -> void:
	if not rendered:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://output/bridges")
	root.get_texture().get_image().save_png("res://output/bridges/" + label + ".png")


func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame


func _check_crossing(deck: Rect2, label: String) -> void:
	var left: Vector2 = Vector2(deck.position.x - 16.0, deck.get_center().y - 3.0)
	var right: Vector2 = Vector2(deck.end.x + 16.0, left.y)
	place(left)
	await _settle()
	var forward: KinematicCollision2D = player.move_and_collide(right - left)
	check(forward == null and player.global_position.distance_to(right) < 0.2, label + " allows real west-to-east traversal")
	var backward: KinematicCollision2D = player.move_and_collide(left - right)
	check(backward == null and player.global_position.distance_to(left) < 0.2, label + " allows real east-to-west traversal")
	place(deck.get_center() - Vector2(0, 3))
	await _settle()
	check(player.test_move(player.global_transform, Vector2(0, -deck.size.y)), label + " prevents leaving its north edge")
	check(player.test_move(player.global_transform, Vector2(0, deck.size.y)), label + " prevents leaving its south edge")
	for x: float in [deck.position.x + 8.0, deck.get_center().x, deck.end.x - 8.0]:
		check(bool(arena.call("is_ground_surface_point", Vector2(x, deck.get_center().y))), label + " supplies continuous deck support")


func _check_rail_shapes(unit: Node2D, label: String) -> void:
	var rails: Array = unit.get_meta(&"rail_rects", []) as Array
	var solid: StaticBody2D = unit.get_node_or_null("Solid") as StaticBody2D
	check(rails.size() == 2, label + " maps two physical rails")
	check(solid != null and solid.collision_layer == 1 and solid.collision_mask == 0, label + " uses world collision without enemy-only masks")
	if solid == null:
		return
	check(solid.get_child_count() == rails.size(), label + " has only the two rail colliders")
	for rail_variant: Variant in rails:
		var rail: Rect2 = rail_variant as Rect2
		var matching_shape: bool = false
		for child: Node in solid.get_children():
			var collider: CollisionShape2D = child as CollisionShape2D
			if collider == null:
				continue
			var rectangle: RectangleShape2D = collider.shape as RectangleShape2D
			if rectangle != null:
				var actual: Rect2 = Rect2(collider.global_position - rectangle.size * 0.5, rectangle.size)
				if actual.is_equal_approx(rail):
					matching_shape = true
		check(matching_shape, label + " collision follows the mapped rail bounds")


func _check_facade(unit: Node2D, label: String) -> void:
	var deck: Rect2 = unit.get_meta(&"deck_rect", Rect2()) as Rect2
	var facade_bounds: Rect2 = unit.get_meta(&"facade_bounds", Rect2()) as Rect2
	var facade: CanvasItem = unit.get_node_or_null("Facade") as CanvasItem
	var front: Node2D = unit.get_node_or_null("FrontRail") as Node2D
	var back: Node2D = unit.get_node_or_null("BackRail") as Node2D
	check(facade != null and facade.z_index == -35, label + " draws its submerged facade above water and below the actor plane")
	check(front != null and back != null and front.z_index == 2 and back.z_index == 2, label + " sorts rails in the actor depth band")
	if front != null and back != null:
		check(front.position.y > back.position.y, label + " places its front rail after the back rail in Y sorting")
	check(facade_bounds.has_area() and facade_bounds.end.y > deck.end.y, label + " facade extends below the traversable deck")
	var unsupported: int = 0
	for y: int in range(ceili(deck.end.y + 4.0), floori(facade_bounds.end.y), 4):
		var point: Vector2 = Vector2(deck.get_center().x, y)
		if facade_bounds.has_point(point) and not bool(arena.call("is_ground_surface_point", point)):
			unsupported += 1
	check(unsupported > 0, label + " decorative submerged facade does not create walkable river support")
	if facade != null:
		check(facade.find_children("*", "CollisionObject2D", true, false).is_empty(), label + " submerged artwork adds no physical volume")
		var mask: Image = facade.get_meta(&"water_mask", null) as Image
		check(mask != null and mask.get_format() == Image.FORMAT_R8, label + " stores a compact local contact mask")
		if mask != null:
			check(mask.get_size() == Vector2i(ceili(facade_bounds.size.x / 4.0), ceili(facade_bounds.size.y / 4.0)), label + " uses four world pixels per mask texel")
			var mismatches: int = 0
			for y: int in range(mask.get_height()):
				for x: int in range(mask.get_width()):
					var point: Vector2 = facade_bounds.position + Vector2(x * 4 + 2, y * 4 + 2)
					var wet: bool = mask.get_pixel(x, y).r > 0.5
					var expected: bool = not bool(arena.call("is_ground_surface_point", point))
					if wet != expected:
						mismatches += 1
					if wet:
						wet_mask_samples += 1
					else:
						dry_mask_samples += 1
			check(mismatches == 0, label + " submersion follows river support and leaves the land anchors dry")


func _check_water_contact() -> void:
	var water: WaterSurface = arena.get_node("Water") as WaterSurface
	var materials: Array = bridge_geometry.get("contact_materials") as Array
	check(materials.size() == 2, "Each independent bridge has one local facade contact material")
	var seconds: float = 23.75
	water.set_process(false)
	water.set_elapsed(seconds)
	await process_frame
	await process_frame
	check(is_equal_approx(float(bridge_geometry.get("water_elapsed")), seconds), "Bridge contact clock follows Water.elapsed")
	for material_variant: Variant in materials:
		var material: ShaderMaterial = material_variant as ShaderMaterial
		check(material != null and material.shader != null, "Bridge contact uses a compiled ShaderMaterial")
		if material == null or material.shader == null:
			continue
		check(is_equal_approx(float(material.get_shader_parameter(&"water_elapsed")), seconds), "All facades use the same controlled water clock")
		var source: String = material.shader.code
		check(not source.contains("hint_screen_texture") and not source.contains("SCREEN_TEXTURE"), "Contact effect needs no full-screen copy or screen read")
		check(not source.contains("TIME"), "Contact animation has no independent shader TIME clock")
		check(material.get_shader_parameter(&"waterline_y") != null, "Facade maps an explicit waterline")
	water.set_process(true)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(640, 360)
	arena = (load("res://scenes/maps/open_world.tscn") as PackedScene).instantiate() as Node2D
	arena.set("warp_entry_cutscene_enabled", false)
	root.add_child(arena)
	current_scene = arena
	check(await wait_until(func() -> bool: return bool(arena.get("entry_complete"))), "Open world finishes its entry")
	player = arena.get_node("Nox") as Player
	player.set_physics_process(false)
	player.get_node("BoosterShooter").set_process(false)
	player.get_node("GameplayKit").process_mode = Node.PROCESS_MODE_DISABLED
	player.contact_invulnerability = 1000.0
	var map_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(arena.get("map_path")))) as Dictionary
	var composition: Dictionary = preload("res://scripts/dungeon/ldtk_level_composition.gd").compose(map_data, "Room_2")
	var authored_hash: int = map_data.hash()
	var definitions: Dictionary = {}
	for definition: Dictionary in map_data.defs.tilesets:
		definitions[int(definition.uid)] = definition
	var prepared: Array = BRIDGES.prepare_layers(composition.layers as Array, definitions)
	check(map_data.hash() == authored_hash, "Bridge preparation preserves the exact authored LDtk data")
	var runtime_layers: Array = arena.get("_level_layers") as Array
	check(runtime_layers.hash() == prepared.hash(), "The real terrain pipeline consumes prepared bridge layers before building support")
	_check_atlas(map_data, prepared)
	var decks: Array[Rect2] = _bridge_components(prepared)
	_check_approaches(prepared, decks)
	authored_size = Vector2(float(composition.primary.pxWid), float(composition.primary.pxHei))
	bridge_geometry = arena.get_node_or_null("BridgeGeometry") as Node2D
	check(bridge_geometry != null, "Bridge adapter is part of the actual open-world scene")
	if bridge_geometry == null:
		quit(1)
		return
	var units: Array = bridge_geometry.get("bridges") as Array
	check(units.size() == 2 and decks.size() == 2, "Two painted bridge components produce two independent runtime bridges")
	for index: int in range(mini(units.size(), decks.size())):
		var unit: Node2D = units[index] as Node2D
		var deck: Rect2 = unit.get_meta(&"deck_rect", Rect2()) as Rect2
		var label: String = "Bridge " + str(index + 1)
		check(decks.has(deck), label + " derives its deck from the authored Floor_Bridges paint")
		await _check_crossing(deck, label)
		_check_rail_shapes(unit, label)
		_check_facade(unit, label)
		place(deck.get_center() - Vector2(0, 3))
		await create_timer(0.2).timeout
		await capture("0%d_bridge" % [index + 1])
		if rendered:
			place(Vector2(deck.get_center().x, deck.position.y + 5.0))
			await create_timer(0.1).timeout
			await capture("bridge_%d_back_rail" % [index + 1])
			place(Vector2(deck.get_center().x, deck.end.y - 8.0))
			await create_timer(0.1).timeout
			await capture("bridge_%d_front_rail" % [index + 1])
	await _check_water_contact()
	# Current authoring places every pier in the river; dry land anchors are
	# optional. Each contact texel was already checked against actual support.
	check(wet_mask_samples > 0, "Authored submerged river masonry exercises the contact mask")
	if rendered:
		for index: int in range(units.size()):
			var unit: Node2D = units[index] as Node2D
			var deck: Rect2 = unit.get_meta(&"deck_rect", Rect2()) as Rect2
			place(deck.get_center() - Vector2(0, 3))
			await create_timer(0.15).timeout
			await capture("0%d_water_contact" % [index + 3])
		await _overview()
	print("BRIDGES_REGRESSION " + ("PASS" if failures.is_empty() else "FAIL " + str(failures.size())))
	quit(0 if failures.is_empty() else 1)
