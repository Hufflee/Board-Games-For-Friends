extends RefCounted
## Ассеты текущей игры: только безопасные байты из авторской папки или проверенного кэша.

const Library := preload("res://games/custom/logic/cg_library.gd")
const Package := preload("res://games/custom/logic/cg_package.gd")
var files: Dictionary = {}
var textures: Dictionary = {}
var fonts: Dictionary = {}
var key := ""

## Текущий черновик может содержать ещё не сохранённые в game.json ассеты.
func configure_document(definition: Dictionary) -> void:
	var uuid := str(definition.get("id", ""))
	var next := uuid + "/draft/" + str(JSON.stringify(definition.get("assets", {})).hash())
	if next == key:
		return
	key = next
	files = {}
	textures.clear()
	fonts.clear()
	if not Library.uuid_valid(uuid):
		return
	var loaded := 0
	for hash_value: String in definition.get("assets", {}):
		var entry: Variant = definition.assets[hash_value]
		if not entry is Dictionary:
			continue
		var path := str(entry.get("path", ""))
		if not Package.path_valid(path) or not path.begins_with("assets/") or path.get_file().get_basename() != hash_value:
			continue
		var file := FileAccess.open(Library.folder(uuid) + "/" + path, FileAccess.READ)
		if file == null or file.get_length() > Package.LIMIT - loaded:
			continue
		var supplied := file.get_buffer(file.get_length())
		if Package.sha(supplied) == hash_value:
			files[path] = supplied
			loaded += supplied.size()

func configure(uuid: String, hash_value: String, author: bool) -> void:
	var next := uuid + "/" + hash_value
	if next == key:
		return
	key = next
	textures.clear()
	fonts.clear()
	files = {}
	if author:
		files = Library.files_for(uuid)
	elif Package.hash_valid(hash_value):
		var cached := Library.cached(hash_value)
		if str(cached.error).is_empty():
			files = cached.files

func bytes(hash_value: String, extensions: Array) -> Dictionary:
	if not Package.hash_valid(hash_value):
		return {}
	for extension: String in extensions:
		var directory := "fonts" if extension in ["ttf", "otf"] else "img"
		var path := "assets/" + directory + "/" + hash_value + "." + extension
		if files.has(path) and files[path] is PackedByteArray and (files[path] as PackedByteArray).size() <= Package.LIMIT and Package.sha(files[path]) == hash_value:
			return {"data": files[path], "extension": extension}
	return {}

func image(hash_value: String) -> Texture2D:
	if textures.has(hash_value):
		return textures[hash_value]
	var asset := bytes(hash_value, ["png", "jpg", "webp"])
	if asset.is_empty():
		return null
	var decoded := Package.image_from_bytes(asset.data, asset.extension)
	var texture := ImageTexture.create_from_image(decoded) if decoded != null else null
	textures[hash_value] = texture
	return texture

func font(hash_value: String) -> Font:
	if fonts.has(hash_value):
		return fonts[hash_value]
	var asset := bytes(hash_value, ["ttf", "otf"])
	if asset.is_empty() or (asset.data as PackedByteArray).size() > Package.FONT_LIMIT:
		return null
	var resource := FontFile.new()
	resource.data = asset.data
	fonts[hash_value] = resource
	return resource
