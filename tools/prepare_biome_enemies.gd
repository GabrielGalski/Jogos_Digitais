extends SceneTree
## Atlas regions keep the original sheets intact, fixed 32x32 canvas and row order.
const SOURCES: Dictionary[String, String] = {
	"flying_skull": "res://assets/enemies/flying skull/dungeon_flying_skull.png",
	"slime": "res://assets/enemies/slime/dungeon_slime.png",
}
const COUNTS: Dictionary[String, Array] = {"flying_skull": [10, 6, 2, 7], "slime": [6, 12, 2, 6]}
const CLIPS: Array[StringName] = [&"idle", &"attack", &"hit", &"death"]


func _initialize() -> void:
	var manifest: Dictionary = {}
	for kind: String in SOURCES:
		var sheet: Texture2D = load(SOURCES[kind]) as Texture2D
		assert(sheet != null)
		var frames: SpriteFrames = SpriteFrames.new()
		frames.remove_animation(&"default")
		for row: int in range(CLIPS.size()):
			var clip: StringName = CLIPS[row]
			frames.add_animation(clip)
			frames.set_animation_loop(clip, clip == &"idle")
			frames.set_animation_speed(clip, 12.0 if clip == &"idle" else 14.0)
			for index: int in range(int(COUNTS[kind][row])):
				var atlas: AtlasTexture = AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(index * 32, row * 32, 32, 32)
				frames.add_frame(clip, atlas)
		var destination: String = "res://resources/enemies/%s" % kind
		DirAccess.make_dir_recursive_absolute(destination)
		assert(ResourceSaver.save(frames, destination.path_join("frames.tres")) == OK)
		manifest[kind] = {"source": SOURCES[kind], "sha256": FileAccess.get_sha256(SOURCES[kind]), "counts": COUNTS[kind], "canvas": [32, 32]}
	var profile_path: String = "res://resources/enemies/slime/profile.tres"
	if not FileAccess.file_exists(profile_path):
		var script: Script = load("res://scripts/enemies/slime_profile.gd") as Script
		assert(ResourceSaver.save(script.new() as Resource, profile_path) == OK)
	DirAccess.make_dir_recursive_absolute("res://output/biome_enemies")
	var output: FileAccess = FileAccess.open("res://output/biome_enemies/assets.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("BIOME_ASSETS skull=25 slime=26; original sheets preserved")
	quit()
