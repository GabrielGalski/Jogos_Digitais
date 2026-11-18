extends SceneTree
## Lossless 90x64 frame extraction and crystal-only palette normalization.
## ImageGen colour studies live in output/elemental_golem/references; geometry
## always comes from the authored sheets, never the rescaled colour studies.

const ROOT: String = "res://assets/enemies/golem"
const ATTACK: Script = preload("res://scripts/bosses/elemental_golem/attack_frames.gd")
const ACTIONS: Array[String] = ["idle", "walk", "attack", "hurt", "die"]
const ELEMENTS: Array[String] = ["ice", "fire", "lightning"]
const CRYSTALS: Array[String] = ["0e2385", "1047ad", "36a0f1", "90d8ff", "9dd2fa"]
const PALETTES: Dictionary = {
	"ice": ["0e2385", "1047ad", "36a0f1", "90d8ff", "9dd2fa"],
	"fire": ["872b24", "c65326", "ff963b", "ffe4a0", "ffeabb"],
	"lightning": ["806321", "bb942b", "f7dc49", "fff8bb", "fffbd6"],
}

func _initialize() -> void:
	if "--resources" in OS.get_cmdline_user_args():
		_build_resources()
	else:
		_extract()
	quit()


func _extract() -> void:
	var manifest: Dictionary = {"canvas": [90, 64], "feet_pivot": [45, 64],
		"cast_pose": 6, "jump_prepare_poses": [3, 4], "fall_pose": 7,
		"attack_map": ATTACK.manifest(),
		"crystal_source_colors": CRYSTALS, "palettes": PALETTES, "animations": {}}
	var total: int = 0
	for action: String in ACTIONS:
		var source_path: String = ROOT + "/Golem_1_%s.png" % action
		var source: Image = _read_source(source_path)
		assert(source.get_width() % 90 == 0 and source.get_height() == 64)
		var count: int = floori(float(source.get_width()) / 90.0)
		(manifest.animations as Dictionary)[action] = {"frames": count,
			"source": source_path, "sha256": FileAccess.get_sha256(source_path)}
		if action == "die":
			var visible_pose: int = _last_visible_pose(source)
			manifest["death_map"] = {"last_visible_pose":visible_pose,"remains_pose":visible_pose,
				"runtime_frames":visible_pose,"trailing_empty_cells":count-visible_pose}
		for element: String in ELEMENTS:
			var directory: String = ROOT + "/frames/%s/%s" % [element, action]
			DirAccess.make_dir_recursive_absolute(directory)
			for index: int in range(count):
				var frame: Image = source.get_region(Rect2i(index * 90, 0, 90, 64))
				for y: int in range(64):
					for x: int in range(90):
						var original: Color = frame.get_pixel(x, y)
						var palette_index: int = CRYSTALS.find(original.to_html(false))
						if original.a > 0.0 and palette_index >= 0:
							frame.set_pixel(x, y, Color((PALETTES[element] as Array)[palette_index]))
				assert(frame.save_png(directory + "/%s_%02d.png" % [action, index + 1]) == OK)
				total += 1
	var mapping: FileAccess = FileAccess.open(ROOT + "/sprite_map.json", FileAccess.WRITE)
	mapping.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("[GOLEM ASSETS] extracted=", total, " source pixels/alpha/pivots preserved")


func _build_resources() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/enemies/elemental_golem")
	for element: String in ELEMENTS:
		var frames: SpriteFrames = SpriteFrames.new()
		frames.remove_animation(&"default")
		for action: String in ACTIONS:
			frames.add_animation(action)
			frames.set_animation_loop(action, action == "idle" or action == "walk")
			frames.set_animation_speed(action, 9.0 if action == "idle" else 12.0)
			var source: Image = _read_source(ROOT + "/Golem_1_%s.png" % action)
			var count: int = _last_visible_pose(source) if action == "die" else floori(float(source.get_width()) / 90.0)
			for index: int in range(count):
				var texture: Texture2D = load(ROOT + "/frames/%s/%s/%s_%02d.png" % [element, action, action, index + 1]) as Texture2D
				frames.add_frame(action, texture)
		for clip: String in ATTACK.CLIPS:
			frames.add_animation(clip)
			frames.set_animation_loop(clip, clip == "cast" or clip == "slam")
			frames.set_animation_speed(clip, 9.0)
			for index: int in ATTACK.CLIPS[clip]:
				frames.add_frame(clip, frames.get_frame_texture(&"attack", index))
		frames.set_animation_speed(&"charge", float((ATTACK.CLIPS.charge as Array).size())/ATTACK.CHARGE_DURATION)
		assert(ResourceSaver.save(frames, "res://resources/enemies/elemental_golem/%s.tres" % element) == OK)
	print("[GOLEM ASSETS] three SpriteFrames resources saved")


func _last_visible_pose(source: Image) -> int:
	var count: int = floori(float(source.get_width())/90.0)
	while count > 0 and not source.get_region(Rect2i((count-1)*90,0,90,64)).get_used_rect().has_area():
		count -= 1
	return count


func _read_source(path: String) -> Image:
	var result: Image = Image.new()
	assert(result.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK)
	return result
