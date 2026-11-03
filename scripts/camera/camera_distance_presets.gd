extends Resource
## Presentation-only configuration: 1.10 means 10% more visible world, not -10% zoom.

@export var distance_factors: PackedFloat32Array = PackedFloat32Array([1.0, 1.10, 1.20, 1.25])
@export_range(0, 16, 1) var default_index: int = 0
@export var cycling_enabled: bool = true


func view_count() -> int:
	return maxi(distance_factors.size(), 1)


func factor_at(index: int) -> float:
	if distance_factors.is_empty():
		return 1.0
	return maxf(distance_factors[clampi(index, 0, distance_factors.size() - 1)], 0.01)
