extends SceneTree
## Atlas assembly: reuse the four redundant center cells for inner corners.
## The approved source art and all twelve outside-edge pieces remain exact.


func _initialize() -> void:
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/tiles/floor/water_bank_tileset_64.png"))
	if source == null or source.get_size() != Vector2i(64, 64):
		quit(1)
		return
	var mapped: Image = source.duplicate() as Image
	var ground: Color = Color("#533048")
	# Reverse which side of an existing corner is land; keep every rock pixel.
	# source outer SE/SW/NE/NW becomes inner NW/NE/SW/SE respectively.
	for pair: Vector2i in [Vector2i(15, 5), Vector2i(12, 6), Vector2i(3, 9), Vector2i(0, 10)]:
		var from: Vector2i = Vector2i(pair.x % 4 * 16, floori(float(pair.x) / 4.0) * 16)
		var to: Vector2i = Vector2i(pair.y % 4 * 16, floori(float(pair.y) / 4.0) * 16)
		for y: int in range(16):
			for x: int in range(16):
				var color: Color = source.get_pixelv(from + Vector2i(x, y))
				if color.a < 0.5: color = ground
				elif color.is_equal_approx(ground): color = Color.TRANSPARENT
				mapped.set_pixelv(to + Vector2i(x, y), color)
	var error: Error = mapped.save_png("res://assets/tiles/floor/water_bank_tileset_64_mapped.png")
	print("WATER_BANK_CORNERS " + ("PASS" if error == OK else "FAIL"))
	quit(0 if error == OK else 1)
