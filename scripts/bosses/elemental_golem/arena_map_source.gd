extends RefCounted
## Cache just the selected room; validate against the LDtk bytes on every load.
const COMPOSITION: Script = preload("res://scripts/dungeon/ldtk_level_composition.gd")
const CACHE_VERSION: int = 1
static var _memory: Dictionary[String, Dictionary] = {}


static func read(path: String, level_name: String) -> Dictionary:
	var digest: String = FileAccess.get_sha256(path)
	var key: String = str(CACHE_VERSION) + ":" + path + ":" + level_name + ":" + digest
	if _memory.has(key): return _memory[key]
	var cache_path: String = "user://elemental_room_" + (path + level_name).sha256_text().substr(0, 16) + ".cache"
	if FileAccess.file_exists(cache_path):
		var cached_file: FileAccess = FileAccess.open(cache_path, FileAccess.READ)
		if cached_file != null:
			var cached: Variant = cached_file.get_var()
			if cached is Dictionary and cached.get("key") == key and cached.get("room") is Dictionary:
				_memory[key] = cached.room as Dictionary
				return _memory[key]
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary: return {"ok": false, "error": "Elemental LDtk: invalid map " + path}
	var data: Dictionary = raw as Dictionary
	var composition: Dictionary = COMPOSITION.compose(data, level_name)
	if not bool(composition.get("ok", false)): return composition
	var level: Dictionary = composition.primary as Dictionary
	var selected: Dictionary = {"ok": true, "primary": {"pxWid": level.pxWid, "pxHei": level.pxHei},
		"layers": composition.layers, "tilesets": (data.defs as Dictionary).tilesets}
	_memory.clear() # Keep one room rather than every revision saved during editing.
	_memory[key] = selected
	var cache_file: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
	if cache_file != null: cache_file.store_var({"key": key, "room": selected})
	return selected
