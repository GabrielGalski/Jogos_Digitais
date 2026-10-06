extends RefCounted
## Shared direct PNG textures. Debug previews refresh without palette generation.

var _textures: Dictionary[String, Texture2D] = {}
var _hashes: Dictionary[String, String] = {}
var _images: Dictionary[String, Image] = {}


func get_texture(relative_path: String) -> Texture2D:
	var path: String = "res://" + relative_path.trim_prefix("res://").replace("\\", "/")
	if _textures.has(path):
		return _textures[path]
	var texture: Texture2D = null
	if OS.is_debug_build() and FileAccess.file_exists(path):
		var source: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if source != null and not source.is_empty():
			texture = ImageTexture.create_from_image(source)
			_images[path] = source
			_hashes[path] = FileAccess.get_md5(path)
	if texture == null:
		texture = load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
	return texture


func get_source_image(relative_path: String) -> Image:
	var path: String = "res://" + relative_path.trim_prefix("res://").replace("\\", "/")
	var texture: Texture2D = get_texture(relative_path)
	if _images.has(path):
		return _images[path]
	return texture.get_image() if texture != null else null


func refresh() -> int:
	var changed: int = 0
	for path: String in _hashes:
		if not FileAccess.file_exists(path):
			continue
		var digest: String = FileAccess.get_md5(path)
		if digest.is_empty() or digest == _hashes[path]:
			continue
		var source: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if source == null or source.is_empty():
			continue
		var texture: ImageTexture = _textures[path] as ImageTexture
		if texture == null:
			continue
		texture.set_image(source)
		_images[path] = source
		_hashes[path] = digest
		changed += 1
	return changed
