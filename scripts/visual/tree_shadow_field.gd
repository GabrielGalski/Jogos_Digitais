extends RefCounted
## Project authored crown silhouettes onto the ground once, then join only
## neighbouring forest gaps. One R8 union is cached; gameplay does no bake work.

const VERSION: int = 4
const CACHE_DIRECTORY: String = "user://visual_cache/tree_shadows/"
const SAME_TERRAIN_TOLERANCE: float = 0.5


static func build(casters: Array, profile: Resource, use_cache: bool = true) -> Dictionary:
	if casters.is_empty(): return {}
	var started: int = Time.get_ticks_usec()
	var sample_size: int = maxi(int(profile.get("world_pixels_per_texel")), 2)
	var settings: Dictionary = {
		"crown_scale": profile.get("crown_scale") as Vector2,
		"direction": (profile.get("projection_direction") as Vector2).normalized(),
		"length": maxf(float(profile.get("projection_length")), 0.0),
		"compression": maxf(float(profile.get("projection_compression")), 0.05),
		"height": maxf(float(profile.get("crown_height_px")), 1.0),
		"contact": (profile.get("contact_radius") as Vector2).max(Vector2.ZERO),
		"forest_scale": maxf(float(profile.get("forest_crown_scale")), 0.0),
		"gap": maxf(float(profile.get("forest_gap_px")), 0.0),
		"link_distance": maxf(float(profile.get("forest_max_link_distance")), 0.0),
	}
	var descriptions: Array[Dictionary] = _canonical_descriptions(casters, float(settings.height))
	if descriptions.is_empty(): return {}
	# Colour and strength belong to the one draw call, never to cached geometry.
	var key: String = var_to_str([VERSION, sample_size, settings, descriptions]).sha256_text()
	var cache_path: String = CACHE_DIRECTORY + key + ".png"
	if use_cache:
		var cached: Dictionary = _read_cache(cache_path, key, descriptions.size(), sample_size, started)
		if not cached.is_empty(): return cached
	var geometry: Dictionary = _geometry(descriptions, settings)
	var polygons: Array[PackedVector2Array] = geometry.polygons as Array[PackedVector2Array]
	if polygons.is_empty(): return {}
	var bounds: Rect2 = Rect2()
	for polygon: PackedVector2Array in polygons:
		var rect: Rect2 = _polygon_bounds(polygon)
		bounds = bounds.merge(rect) if bounds.has_area() else rect
	bounds = bounds.grow(float(sample_size))
	var first: Vector2 = (bounds.position / float(sample_size)).floor() * float(sample_size)
	var ending: Vector2 = (bounds.end / float(sample_size)).ceil() * float(sample_size)
	bounds = Rect2(first, ending - first)
	var size: Vector2i = Vector2i(bounds.size / float(sample_size))
	var image: Image = _rasterize(polygons, bounds, size, sample_size)
	var field: Dictionary = {"image": image, "bounds": bounds, "sample_size": sample_size, "key": key,
		"cache_hit": false, "caster_count": descriptions.size(), "bytes": image.get_data().size(),
		"build_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"polygon_count": polygons.size(), "forest_link_count": geometry.link_count,
		"source_vertex_count": geometry.source_vertex_count}
	if use_cache: _write_cache(cache_path, field)
	field.build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	return field


static func _read_cache(cache_path: String, key: String, caster_count: int, sample_size: int, started: int) -> Dictionary:
	var metadata_path: String = cache_path.trim_suffix(".png") + ".json"
	if not FileAccess.file_exists(cache_path) or not FileAccess.file_exists(metadata_path): return {}
	var stream: FileAccess = FileAccess.open(metadata_path, FileAccess.READ)
	if stream == null: return {}
	var raw: Variant = JSON.parse_string(stream.get_as_text())
	stream.close()
	if not raw is Dictionary: return {}
	var metadata: Dictionary = raw as Dictionary
	for statistic: String in ["version", "caster_count", "sample_size", "polygon_count", "forest_link_count", "source_vertex_count", "bytes"]:
		if not _is_count(metadata.get(statistic, null)): return {}
	if int(metadata.get("version", -1)) != VERSION or str(metadata.get("key", "")) != key: return {}
	if int(metadata.get("caster_count", -1)) != caster_count or int(metadata.get("sample_size", -1)) != sample_size: return {}
	var raw_bounds: Variant = metadata.get("bounds", null)
	var raw_size: Variant = metadata.get("size", null)
	if not raw_bounds is Array or not raw_size is Array: return {}
	var rect_values: Array = raw_bounds as Array
	var size_values: Array = raw_size as Array
	if rect_values.size() != 4 or size_values.size() != 2: return {}
	for value: Variant in rect_values + size_values:
		if not (value is float or value is int) or not is_finite(float(value)): return {}
	var bounds: Rect2 = Rect2(float(rect_values[0]), float(rect_values[1]), float(rect_values[2]), float(rect_values[3]))
	var size: Vector2i = Vector2i(int(size_values[0]), int(size_values[1]))
	if not bounds.has_area() or size.x <= 0 or size.y <= 0: return {}
	if not bounds.size.is_equal_approx(Vector2(size) * float(sample_size)): return {}
	if not (bounds.position / float(sample_size)).is_equal_approx((bounds.position / float(sample_size)).round()): return {}
	if int(metadata.polygon_count) == 0 or int(metadata.bytes) != size.x * size.y: return {}
	var png: PackedByteArray = FileAccess.get_file_as_bytes(cache_path)
	if png.is_empty() or str(metadata.get("png_sha256", "")) != _png_digest(png): return {}
	var image: Image = Image.new()
	if image.load_png_from_buffer(png) != OK or image.get_size() != size: return {}
	image.convert(Image.FORMAT_R8)
	return {"image": image, "bounds": bounds, "sample_size": sample_size, "key": key,
		"cache_hit": true, "caster_count": caster_count, "bytes": image.get_data().size(),
		"build_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"polygon_count": int(metadata.polygon_count), "forest_link_count": int(metadata.forest_link_count),
		"source_vertex_count": int(metadata.source_vertex_count)}


static func _is_count(value: Variant) -> bool:
	if not (value is float or value is int): return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number == floorf(number)


static func _png_digest(png: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(png)
	return context.finish().hex_encode()


static func _write_cache(cache_path: String, field: Dictionary) -> void:
	if DirAccess.make_dir_recursive_absolute(CACHE_DIRECTORY) != OK: return
	var image: Image = field.image as Image
	if image.save_png(cache_path) != OK: return
	var bounds: Rect2 = field.bounds as Rect2
	var metadata: Dictionary = {"version": VERSION, "key": str(field.key),
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"size": [image.get_width(), image.get_height()], "sample_size": int(field.sample_size),
		"caster_count": int(field.caster_count), "bytes": int(field.bytes),
		"polygon_count": int(field.polygon_count), "forest_link_count": int(field.forest_link_count),
		"source_vertex_count": int(field.source_vertex_count),
		"png_sha256": _png_digest(FileAccess.get_file_as_bytes(cache_path))}
	var stream: FileAccess = FileAccess.open(cache_path.trim_suffix(".png") + ".json", FileAccess.WRITE)
	if stream != null:
		stream.store_string(JSON.stringify(metadata))
		stream.close()


static func _canonical_descriptions(casters: Array, default_height: float) -> Array[Dictionary]:
	var descriptions: Array[Dictionary] = []
	for raw: Variant in casters:
		if not raw is Dictionary: continue
		var caster: Dictionary = raw as Dictionary
		if float(caster.get("weight", 1.0)) <= 0.0: continue
		var crowns: Array[PackedVector2Array] = []
		var supplied: Array = caster.get("crowns", []) as Array
		for item: Variant in supplied:
			if item is PackedVector2Array and (item as PackedVector2Array).size() >= 3:
				crowns.append(item as PackedVector2Array)
		if crowns.is_empty():
			var crown: PackedVector2Array = caster.get("crown", PackedVector2Array()) as PackedVector2Array
			if crown.size() >= 3: crowns.append(crown)
		if crowns.is_empty() and not bool(caster.get("contact_enabled", true)): continue
		var crown_bounds: Rect2 = Rect2()
		if not crowns.is_empty(): crown_bounds = _polygon_bounds(crowns[0])
		for crown: PackedVector2Array in crowns:
			crown_bounds = crown_bounds.merge(_polygon_bounds(crown))
		var record: Dictionary = {
			"anchor": caster.get("anchor", Vector2.ZERO) as Vector2,
			"crowns": crowns,
			"crown_center": caster.get("crown_center", crown_bounds.get_center()) as Vector2,
			"crown_height": maxf(float(caster.get("crown_height", default_height)), 0.0),
			"terrain_height": float(caster.get("terrain_height", 0.0)),
			"source_hash": str(caster.get("source_hash", "")),
			"contact_enabled": bool(caster.get("contact_enabled", true)),
			"weight": float(caster.get("weight", 1.0)),
			"scale": caster.get("scale", Vector2.ONE) as Vector2,
		}
		record["canonical"] = var_to_str(record)
		descriptions.append(record)
	descriptions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.canonical) < str(b.canonical))
	return descriptions


static func _geometry(casters: Array[Dictionary], settings: Dictionary) -> Dictionary:
	var polygons: Array[PackedVector2Array] = []
	var ambient: Array[Dictionary] = []
	var contact: Vector2 = settings.contact as Vector2
	var crown_scale: Vector2 = settings.crown_scale as Vector2
	var projection_scale: Vector2 = crown_scale * Vector2(1.0, float(settings.compression))
	var forest_scale: Vector2 = Vector2(1.0, float(settings.compression)) * float(settings.forest_scale)
	var source_vertex_count: int = 0
	for caster_index: int in range(casters.size()):
		var caster: Dictionary = casters[caster_index]
		var crowns: Array[PackedVector2Array] = caster.crowns as Array[PackedVector2Array]
		var anchor: Vector2 = caster.anchor as Vector2
		var local_scale: Vector2 = caster.scale as Vector2
		var crown_center: Vector2 = caster.crown_center as Vector2
		var projection: Vector2 = (settings.direction as Vector2) * float(settings.length) * float(caster.crown_height) / float(settings.height)
		for crown: PackedVector2Array in crowns:
			var projected: PackedVector2Array = PackedVector2Array()
			var coverage: PackedVector2Array = PackedVector2Array()
			for point: Vector2 in crown:
				var local: Vector2 = (point - crown_center) * local_scale
				projected.append(anchor + local * projection_scale + projection)
				coverage.append(anchor + local * forest_scale - Vector2(0.0, contact.y))
			polygons.append(projected)
			if float(settings.forest_scale) > 0.0:
				polygons.append(coverage)
				ambient.append({"anchor": anchor, "polygon": coverage, "caster_index": caster_index,
					"bounds": _polygon_bounds(coverage), "terrain_height": caster.terrain_height})
			source_vertex_count += crown.size()
		if bool(caster.contact_enabled) and contact.x > 0.0 and contact.y > 0.0:
			polygons.append(_rounded_contact(anchor, contact * local_scale.abs()))
	var links: Array[PackedVector2Array] = _forest_links(ambient, float(settings.gap), float(settings.link_distance))
	polygons.append_array(links)
	return {"polygons": polygons, "link_count": links.size(), "source_vertex_count": source_vertex_count}


static func _rounded_contact(center: Vector2, radius: Vector2) -> PackedVector2Array:
	var polygon: PackedVector2Array = PackedVector2Array()
	for index: int in range(12):
		var angle: float = float(index) * TAU / 12.0
		polygon.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return polygon


static func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty(): return Rect2()
	var low: Vector2 = polygon[0]
	var high: Vector2 = low
	for point: Vector2 in polygon:
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)


static func _forest_links(crowns: Array[Dictionary], gap: float, max_distance: float) -> Array[PackedVector2Array]:
	var links: Array[PackedVector2Array] = []
	if gap <= 0.0 or max_distance <= 0.0: return links
	# A spatial hash avoids comparing the map against every crown or tree pair.
	var buckets: Dictionary[Vector2i, Array] = {}
	for index: int in range(crowns.size()):
		var cell: Vector2i = Vector2i(((crowns[index].anchor as Vector2) / max_distance).floor())
		if not buckets.has(cell): buckets[cell] = []
		(buckets[cell] as Array).append(index)
	for first_index: int in range(crowns.size()):
		var first: Dictionary = crowns[first_index]
		var anchor: Vector2 = first.anchor as Vector2
		var cell: Vector2i = Vector2i((anchor / max_distance).floor())
		for offset_y: int in range(-1, 2):
			for offset_x: int in range(-1, 2):
				var candidates: Array = buckets.get(cell + Vector2i(offset_x, offset_y), []) as Array
				for candidate: Variant in candidates:
					var second_index: int = int(candidate)
					if second_index <= first_index: continue
					var second: Dictionary = crowns[second_index]
					if int(first.caster_index) == int(second.caster_index): continue
					if anchor.distance_squared_to(second.anchor as Vector2) > max_distance * max_distance: continue
					if absf(float(first.terrain_height) - float(second.terrain_height)) > SAME_TERRAIN_TOLERANCE: continue
					var first_bounds: Rect2 = first.bounds as Rect2
					if not first_bounds.grow(gap).intersects(second.bounds as Rect2): continue
					var first_polygon: PackedVector2Array = first.polygon as PackedVector2Array
					var second_polygon: PackedVector2Array = second.polygon as PackedVector2Array
					if not Geometry2D.intersect_polygons(first_polygon, second_polygon).is_empty(): continue
					var nearest: PackedVector2Array = _nearest_points(first_polygon, second_polygon, gap)
					if nearest.size() == 2:
						links.append(_gap_patch(nearest[0], nearest[1], gap))
	return links


static func _nearest_points(first: PackedVector2Array, second: PackedVector2Array, limit: float) -> PackedVector2Array:
	var best_distance: float = limit * limit + 0.0001
	var result: PackedVector2Array = PackedVector2Array()
	# For disjoint polygon boundaries, a closest pair includes a vertex.
	for pass_index: int in range(2):
		var vertices: PackedVector2Array = first if pass_index == 0 else second
		var edges: PackedVector2Array = second if pass_index == 0 else first
		for vertex: Vector2 in vertices:
			for edge_index: int in range(edges.size()):
				var start: Vector2 = edges[edge_index]
				var ending: Vector2 = edges[(edge_index + 1) % edges.size()]
				var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(vertex, start, ending)
				var distance: float = vertex.distance_squared_to(nearest)
				if distance < best_distance:
					best_distance = distance
					result = PackedVector2Array([vertex, nearest]) if pass_index == 0 else PackedVector2Array([nearest, vertex])
	return result


static func _gap_patch(first: Vector2, second: Vector2, gap: float) -> PackedVector2Array:
	var distance: float = first.distance_to(second)
	var axis: Vector2 = (second - first).normalized()
	if axis.is_zero_approx(): axis = Vector2.RIGHT
	# A short rounded stitch closes only the local gap, not the convex hull of
	# an entire forest pair. Large clearings and irregular outer edges survive.
	var radius: float = clampf(distance * 0.5 + 3.0, 4.0, maxf(minf(gap, 10.0), 4.0))
	var start: Vector2 = first - axis * 2.0
	var ending: Vector2 = second + axis * 2.0
	var angle: float = axis.angle()
	var polygon: PackedVector2Array = PackedVector2Array()
	for index: int in range(7):
		var turn: float = angle + PI * 0.5 + float(index) * PI / 6.0
		polygon.append(start + Vector2(cos(turn), sin(turn)) * radius)
	for index: int in range(7):
		var turn: float = angle - PI * 0.5 + float(index) * PI / 6.0
		polygon.append(ending + Vector2(cos(turn), sin(turn)) * radius)
	return polygon


static func _rasterize(polygons: Array[PackedVector2Array], bounds: Rect2, size: Vector2i, sample_size: int) -> Image:
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(size.x * size.y)
	pixels.fill(0)
	for polygon: PackedVector2Array in polygons:
		var local: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in polygon:
			local.append((point - bounds.position) / float(sample_size))
		var rect: Rect2 = _polygon_bounds(local)
		var first_row: int = maxi(floori(rect.position.y), 0)
		var last_row: int = mini(ceili(rect.end.y), size.y)
		# Scanline fill visits only local polygon spans. Interior is binary 255;
		# fractional boundary samples reconstruct a contour, never a penumbra.
		for y: int in range(first_row, last_row):
			var coverage: PackedFloat32Array = PackedFloat32Array()
			var first_column: int = maxi(floori(rect.position.x), 0)
			var last_column: int = mini(ceili(rect.end.x), size.x)
			coverage.resize(maxi(last_column - first_column, 0))
			coverage.fill(0.0)
			for subrow: int in range(2):
				var scan_y: float = float(y) + 0.25 + float(subrow) * 0.5
				var crossings: PackedFloat32Array = PackedFloat32Array()
				for edge_index: int in range(local.size()):
					var start: Vector2 = local[edge_index]
					var ending: Vector2 = local[(edge_index + 1) % local.size()]
					if (start.y <= scan_y and ending.y > scan_y) or (ending.y <= scan_y and start.y > scan_y):
						crossings.append(start.x + (scan_y - start.y) * (ending.x - start.x) / (ending.y - start.y))
				crossings.sort()
				for crossing: int in range(0, crossings.size() - 1, 2):
					var left: float = crossings[crossing]
					var right: float = crossings[crossing + 1]
					for x: int in range(maxi(floori(left), first_column), mini(ceili(right), last_column)):
						coverage[x - first_column] += maxf(minf(float(x + 1), right) - maxf(float(x), left), 0.0) * 0.5
			for column: int in range(coverage.size()):
				var index: int = y * size.x + first_column + column
				pixels[index] = maxi(pixels[index], roundi(coverage[column] * 255.0))
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, pixels)
