extends RefCounted
## Normalized coast semantics. Neither LDtk nor gameplay dependencies.

enum Kind { DEFAULT, ROCK, BEACH, RAISED, NONE }
const NAMES: Array[String] = ["Default", "Rock", "Beach", "Raised", "None"]
# Foam gain, relative shallow width, elevated contact shadow.
const APPEARANCE: Array[Vector3] = [Vector3(1, 1, 0), Vector3(1.15, 0.8, 0),
	Vector3(0.7, 1.35, 0), Vector3(0.45, 0.65, 1), Vector3(0, 1, 0)]


static func kind_from_name(value: String) -> int:
	return NAMES.find(value)


static func style_at(point: Vector2, base_kind: int, overrides: Array[Dictionary]) -> int:
	# The adapter sorts by ascending priority, then stable IID; last match wins.
	var kind: int = clampi(base_kind, 0, Kind.NONE)
	for area: Dictionary in overrides:
		var rect: Rect2 = area.rect
		if rect.has_point(point):
			kind = int(area.kind)
	return kind
