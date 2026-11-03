extends Node2D
## One draw list for active scraps or one static floor chunk. Geometry is shared.
var pieces: Array[RefCounted] = []
var textures: Array[Texture2D] = []
var draw_origin: Vector2 = Vector2.ZERO
var airborne: bool = false
var next_expiry: float = INF


func _draw() -> void:
	var interpolation: float = Engine.get_physics_interpolation_fraction() if airborne else 1.0
	for piece: RefCounted in pieces:
		var ground: Vector2 = (piece.get("previous_ground") as Vector2).lerp(piece.get("ground") as Vector2, interpolation)
		var height: float = lerpf(float(piece.get("previous_height")), float(piece.get("height")), interpolation)
		var profile: Resource = piece.get("profile") as Resource
		var falling: bool = bool(piece.get("falling"))
		var alpha: float = float(piece.get("opacity"))
		if falling:
			alpha *= 1.0 - clampf(float(piece.get("fall_elapsed")) / float(profile.get("void_fall_duration")), 0.0, 1.0)
		elif airborne and height > 2.0:
			# A tiny detached shadow sells height without adding light or glow.
			draw_rect(Rect2((ground - draw_origin).round() + Vector2(-1, 0), Vector2(2, 1)), Color(0.025, 0.015, 0.04, 0.28 * alpha))
		var point: Vector2 = (ground - draw_origin - Vector2(0, height)).round()
		var texture: Texture2D = textures[int(piece.get("texture_index"))]
		# Quarter turns retain exact one-pixel outlines; no smooth sprite rotation.
		var pose: float = roundf(float(piece.get("angle")) / (PI * 0.5)) * PI * 0.5
		draw_set_transform(point, pose, Vector2.ONE)
		draw_texture(texture, -(texture.get_size() * 0.5).floor(), Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO)
