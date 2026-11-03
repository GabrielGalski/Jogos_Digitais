extends RefCounted
## A single north/south river. Authored wet cells -> gated 8-neighbour topology
## -> two continuous banks. The small profile is shared by CPU and shaders.

const GRID: int = 16
const STEP: int = 2
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1), Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1)]
var bounds: Rect2 = Rect2()
var bridges: Array[Rect2] = []
var samples: PackedVector4Array = PackedVector4Array()
var profile_texture: ImageTexture = null
var diagnostics: Array[String] = []
var topology_counts: Dictionary[int, int] = {}
var valid_y: Vector2 = Vector2.ZERO
var locked_west_y: float = 1120.0
var max_visible_shift: float = 0.0
var build_usec: int = 0
var _raw: Dictionary[int, Vector2] = {}


func configure(wet_cells: Dictionary, rect: Rect2, spans: Array[Rect2], west_lock: float, radius: float = 32.0, max_shift: float = 8.0) -> bool:
	var started: int = Time.get_ticks_usec()
	bounds = rect
	bridges = spans
	locked_west_y = west_lock
	samples.clear()
	diagnostics.clear()
	topology_counts.clear()
	_raw.clear()
	max_visible_shift = 0.0
	var rows: Dictionary[int, Array] = {}
	var exposed_banks: Dictionary[int, Vector2] = {}
	for cell: Vector2i in wet_cells:
		if not rows.has(cell.y): rows[cell.y] = []
		(rows[cell.y] as Array).append(cell.x)
		var mask: int = 0
		for index: int in range(8):
			if not wet_cells.has(cell + DIRECTIONS[index]): continue
			# A diagonal belongs to the blob only when both adjacent sides exist.
			if index % 2 == 1 and (not wet_cells.has(cell + DIRECTIONS[index - 1]) or not wet_cells.has(cell + DIRECTIONS[(index + 1) % 8])): continue
			mask |= 1 << index
		topology_counts[mask] = int(topology_counts.get(mask, 0)) + 1
		var exposed: Vector2 = exposed_banks.get(cell.y, Vector2(INF, -INF)) as Vector2
		if (mask & (1 << 6)) == 0: exposed.x = minf(exposed.x, float(cell.x * GRID))
		if (mask & (1 << 2)) == 0: exposed.y = maxf(exposed.y, float((cell.x + 1) * GRID))
		exposed_banks[cell.y] = exposed
	var sorted_y: Array = rows.keys()
	sorted_y.sort()
	if sorted_y.is_empty():
		diagnostics.append("RiverMask esta vazia.")
		return false
	for row: int in sorted_y:
		var xs: Array = rows[row]
		xs.sort()
		if int(xs[-1]) - int(xs[0]) + 1 != xs.size():
			diagnostics.append("RiverMask exige um canal continuo por linha; ilha/ramificacao em Y=" + str(row * GRID))
			return false
		_raw[row] = exposed_banks[row]
	if int(sorted_y[-1]) - int(sorted_y[0]) + 1 != sorted_y.size():
		diagnostics.append("RiverMask possui uma interrupcao entre linhas.")
		return false
	valid_y = Vector2(float(int(sorted_y[0]) * GRID), float((int(sorted_y[-1]) + 1) * GRID))
	var count: int = ceili(bounds.size.y / STEP) + 1
	var image: Image = Image.create_empty(1, count, false, Image.FORMAT_RGBAF)
	for index: int in range(count):
		var y: float = bounds.position.y + index * STEP
		var original: Vector2 = raw_at(y)
		var smoothed: Vector2 = Vector2.ZERO
		var weight_sum: float = 0.0
		var half_window: int = ceili(radius / STEP)
		for offset: int in range(-half_window, half_window + 1):
			var distance: float = float(offset * STEP)
			var weight: float = exp(-0.5 * pow(distance / maxf(radius * 0.45, 1.0), 2.0))
			smoothed += raw_at(y + distance) * weight
			weight_sum += weight
		smoothed /= weight_sum
		smoothed = Vector2(_limit_to_authored(smoothed.x, original.x, y, 0, max_shift), _limit_to_authored(smoothed.y, original.y, y, 1, max_shift))
		# Preserve the elevated west bank and meet its existing foot exactly.
		var west_blend: float = smoothstep(locked_west_y, locked_west_y + radius * 2.0, y)
		smoothed.x = lerpf(original.x, smoothed.x, west_blend)
		var underneath_deck: bool = false
		for deck: Rect2 in bridges:
			if y < deck.position.y - 48.0 or y > deck.end.y + 48.0: continue
			var target: Vector2 = raw_at(deck.position.y + 16.0)
			var influence: float = smoothstep(deck.position.y - 48.0, deck.position.y, y) * (1.0 - smoothstep(deck.end.y, deck.end.y + 48.0, y))
			var pinned: Vector2 = smoothed.lerp(target, influence)
			underneath_deck = y >= deck.position.y and y <= deck.end.y
			# Straighten freely beneath opaque decking; visible banks stay within
			# half a tile of the author's edge, including bridge approaches.
			smoothed = pinned if underneath_deck else Vector2(_limit_to_authored(pinned.x, original.x, y, 0, max_shift), _limit_to_authored(pinned.y, original.y, y, 1, max_shift))
		if not underneath_deck:
			max_visible_shift = maxf(max_visible_shift, maxf(authored_distance(Vector2(smoothed.x, y), 0), authored_distance(Vector2(smoothed.y, y), 1)))
		var active: float = 1.0 if y >= valid_y.x and y <= valid_y.y else 0.0
		var value: Vector4 = Vector4(smoothed.x, smoothed.y, active if y >= locked_west_y else 0.0, active)
		samples.append(value)
		image.set_pixel(0, index, Color(value.x, value.y, value.z, value.w))
	profile_texture = ImageTexture.create_from_image(image)
	build_usec = Time.get_ticks_usec() - started
	return true


func raw_at(y: float) -> Vector2:
	var row: int = clampi(floori(y / GRID), floori(valid_y.x / GRID), floori(valid_y.y / GRID) - 1)
	return _raw.get(row, Vector2(bounds.position.x, bounds.end.x)) as Vector2


func authored_distance(point: Vector2, side: int) -> float:
	# Distance to the entire authored stair contour, including its horizontal
	# ledges. A horizontal X clamp would leave a discontinuity at 32 px steps.
	var best_squared: float = INF
	var row_at_point: int = floori(point.y / GRID)
	for row: int in range(row_at_point - 3, row_at_point + 4):
		var y: float = float(row * GRID)
		var bank: Vector2 = raw_at(y)
		var previous: Vector2 = raw_at(y - GRID)
		var x: float = bank.x if side == 0 else bank.y
		var previous_x: float = previous.x if side == 0 else previous.y
		var vertical: Vector2 = Vector2(x, clampf(point.y, y, y + GRID))
		var horizontal: Vector2 = Vector2(clampf(point.x, minf(x, previous_x), maxf(x, previous_x)), y)
		best_squared = minf(best_squared, minf(point.distance_squared_to(vertical), point.distance_squared_to(horizontal)))
	return sqrt(best_squared)


func _limit_to_authored(candidate: float, original: float, y: float, side: int, limit: float) -> float:
	if authored_distance(Vector2(candidate, y), side) <= limit: return candidate
	var low: float = 0.0
	var high: float = 1.0
	for iteration: int in range(10):
		var middle: float = (low + high) * 0.5
		if authored_distance(Vector2(lerpf(original, candidate, middle), y), side) > limit: high = middle
		else: low = middle
	return lerpf(original, candidate, low)


func banks_at(y: float) -> Vector4:
	if samples.is_empty(): return Vector4.ZERO
	var coordinate: float = clampf((y - bounds.position.y) / STEP, 0.0, samples.size() - 1.0)
	var first: int = floori(coordinate)
	return samples[first].lerp(samples[mini(first + 1, samples.size() - 1)], coordinate - first)


func field_at(point: Vector2) -> Vector2:
	if not bounds.has_point(point) or samples.is_empty(): return Vector2(0.0, 0.0)
	var bank: Vector4 = banks_at(point.y)
	var before: Vector4 = banks_at(point.y - STEP)
	var after: Vector4 = banks_at(point.y + STEP)
	var left: bool = point.x <= (bank.x + bank.y) * 0.5
	var slope: float = (after.x - before.x if left else after.y - before.y) / (STEP * 2.0)
	var distance: float = (point.x - bank.x if left else bank.y - point.x) / sqrt(1.0 + slope * slope)
	return Vector2(distance, bank.z if left else bank.w)


func in_bridge(point: Vector2) -> bool:
	for deck: Rect2 in bridges:
		if deck.has_point(point): return true
	return false


func ground_override(point: Vector2) -> int:
	if in_bridge(point): return 1
	var field: Vector2 = field_at(point)
	return -1 if field.y < 0.5 else 1 if field.x <= 0.0 else 0


func replaces_edge(point: Vector2) -> bool:
	# Keep the top/bottom outer boundary; only replace the two river-facing
	# domains. RiverMask owns this envelope even after a future bank edit;
	# retaining an old edge far from the new bank would create invisible walls.
	if point.y <= valid_y.x or point.y >= valid_y.y: return false
	var field: Vector2 = field_at(point)
	return field.y >= 0.5


func collision_segments() -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for side: int in range(2):
		for index: int in range(samples.size() - 1):
			var y: float = bounds.position.y + index * STEP
			var first: Vector4 = samples[index]
			var last: Vector4 = samples[index + 1]
			var active_first: float = first.z if side == 0 else first.w
			var active_last: float = last.z if side == 0 else last.w
			if minf(active_first, active_last) < 0.5: continue
			var a: Vector2 = Vector2(first.x if side == 0 else first.y, y)
			var b: Vector2 = Vector2(last.x if side == 0 else last.y, y + STEP)
			if in_bridge((a + b) * 0.5): continue
			result.append(a)
			result.append(b)
	return result
