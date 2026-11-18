extends SceneTree
## Lossless 48x48 slicing. Source sheets remain intact; every pose shares a pivot.

const ROOT: String = "res://assets/enemies/insects"
const SOURCES: Dictionary[String, String] = {"tall": "Tall-Enemy", "fly": "Fly-Enemy", "little": "Little-Enemy"}
const COUNTS: Dictionary[String, Dictionary] = {
	"tall": {"idle": 5, "idle_blink": 5, "walk": 4, "attack": 6, "hit": 3, "death": 6},
	"fly": {"idle": 5, "idle_blink": 5, "attack": 6, "hit": 3, "death": 6},
	"little": {"idle": 4, "idle_blink": 4, "walk": 4, "attack": 7, "hit": 3, "death": 6},
}


func _initialize() -> void:
	if "--resources" in OS.get_cmdline_user_args():
		_build_resources()
	else:
		_extract()
	quit()


func _extract() -> void:
	var manifest: Dictionary = {"source_url": "https://sack-pixel.itch.io/pack-enemies-v1",
		"canvas": [48, 48], "feet_pivot": [24, 32], "models": {}}
	var total: int = 0
	for kind: String in SOURCES:
		var clips: Dictionary = {}
		for action: String in COUNTS[kind]:
			var source_action: String = action.capitalize().replace("_", "-")
			if action == "idle_blink": source_action = "Idle-Blink"
			var path: String = ROOT.path_join("%s/Sprite-Sheet/%s-%s-Sheet.png" % [SOURCES[kind], SOURCES[kind], source_action])
			var source: Image = Image.new()
			assert(source.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK, path)
			var count: int = int(COUNTS[kind][action])
			assert(source.get_size() == Vector2i(48 * count, 48), "%s: unexpected canvas %s" % [path, source.get_size()])
			var directory: String = ROOT.path_join("%s/%s" % [kind, action])
			DirAccess.make_dir_recursive_absolute(directory)
			var poses: Array[Dictionary] = []
			for index: int in range(count):
				var rect: Rect2i = Rect2i(index * 48, 0, 48, 48)
				var frame_image: Image = source.get_region(rect)
				var destination: String = directory.path_join("%s_%02d.png" % [action, index + 1])
				if FileAccess.file_exists(destination):
					var previous: Image = Image.new()
					assert(previous.load_png_from_buffer(FileAccess.get_file_as_bytes(destination)) == OK)
					assert(previous.get_data() == frame_image.get_data(), "Refusing to overwrite edited " + destination)
				else:
					assert(frame_image.save_png(destination) == OK)
				poses.append({"file": destination, "source_rect": [rect.position.x, 0, 48, 48], "used_rect": str(frame_image.get_used_rect())})
				total += 1
			clips[action] = {"source": path, "source_sha256": FileAccess.get_sha256(path), "frames": count, "poses": poses}
		(manifest.models as Dictionary)[kind] = clips
	var file: FileAccess = FileAccess.open(ROOT.path_join("sprite_map.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("[INSECT ASSETS] frames=", total, " canvas=48x48 pivot=24,32 source pixels preserved")


func _build_resources() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/enemies/insects")
	for kind: String in SOURCES:
		var frames: SpriteFrames = SpriteFrames.new()
		frames.remove_animation(&"default")
		for action: String in COUNTS[kind]:
			frames.add_animation(action)
			frames.set_animation_loop(action, action in ["idle", "idle_blink", "walk"])
			frames.set_animation_speed(action, 10.0 if action in ["idle", "idle_blink", "walk"] else 14.0)
			for index: int in range(int(COUNTS[kind][action])):
				var path: String = ROOT.path_join("%s/%s/%s_%02d.png" % [kind, action, action, index + 1])
				frames.add_frame(action, load(path) as Texture2D)
		assert(ResourceSaver.save(frames, "res://resources/enemies/insects/%s_frames.tres" % kind) == OK)
	var definitions: Dictionary[String, Dictionary] = {
		"tall": {"maximum_health": 30.0, "damage": 9, "movement_speed": 33.6,
			"body_radius": 7.2, "visual_scale": 1.2, "attack_range": 25.0, "attack_reach": 29.0,
			"windup": 0.72, "active_duration": 0.18, "recovery": 0.36, "attack_cooldown": 0.18,
			"impact_frame": 3, "knockback_resistance": 0.10},
		"fly": {"maximum_health": 6.0, "damage": 3, "movement_speed": 76.0,
			"attack_range": 23.0, "attack_reach": 25.0, "windup": 0.22,
			"active_duration": 0.12, "recovery": 0.24, "attack_cooldown": 0.35,
			"impact_frame": 2, "lunge_speed": 124.0, "retreat_duration": 1.10, "retreat_distance": 76.0},
		"little": {"maximum_health": 9.0, "damage": 6, "movement_speed": 54.0},
	}
	var profile_script: Script = load("res://scripts/enemies/insects/insect_profile.gd") as Script
	for kind: String in definitions:
		var destination: String = "res://resources/enemies/insects/%s.tres" % kind
		if FileAccess.file_exists(destination) and "--reset-profiles" not in OS.get_cmdline_user_args(): continue
		var profile: Resource = profile_script.new() as Resource
		profile.set("kind", StringName(kind))
		for property: String in definitions[kind]: profile.set(property, definitions[kind][property])
		assert(ResourceSaver.save(profile, destination) == OK)
	print("[INSECT ASSETS] three complete SpriteFrames resources saved")
