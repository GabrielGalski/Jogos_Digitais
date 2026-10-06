extends Node2D
## Hall PNG coordinates use the existing (-32, -32) world offset.
## The crates occupy the back of the floor; Nox may only pass in front.

const FLOOR_GEOMETRY: Script = preload("res://scripts/merchant_floor_geometry.gd")

@onready var crates_body: StaticBody3D = $CratesCollider3D
@onready var crates_shape: CollisionShape3D = $CratesCollider3D/CollisionShape3D


func constrain_floor_motion(previous: Vector2, candidate: Vector2) -> Vector2:
	var box: BoxShape3D = crates_shape.shape as BoxShape3D
	if crates_shape.disabled or box == null:
		return candidate
	var center: Vector3 = crates_body.position + crates_shape.position
	var half_width: float = box.size.x * absf(crates_body.scale.x * crates_shape.scale.x) * 0.5
	var half_depth: float = box.size.z * absf(crates_body.scale.z * crates_shape.scale.z) * 0.5
	var crates_left: float = center.x - half_width
	var crates_right: float = center.x + half_width
	var crates_front: float = FLOOR_GEOMETRY.CORRIDOR_TOP + center.z + half_depth
	var old_feet: Vector2 = FLOOR_GEOMETRY.project_floor(previous, 0.0)
	var next_feet: Vector2 = FLOOR_GEOMETRY.project_floor(candidate, 0.0)
	# Resolve the side first, so walking into a crate slides along its edge.
	if old_feet.y < crates_front:
		if old_feet.x <= crates_left and next_feet.x > crates_left:
			next_feet.x = crates_left
		elif old_feet.x >= crates_right and next_feet.x < crates_right:
			next_feet.x = crates_right
	if next_feet.x > crates_left and next_feet.x < crates_right:
		next_feet.y = maxf(next_feet.y, crates_front)
	var depth: float = next_feet.y - FLOOR_GEOMETRY.CORRIDOR_TOP
	return Vector2(next_feet.x + depth * FLOOR_GEOMETRY.DEPTH_SKEW, depth)
