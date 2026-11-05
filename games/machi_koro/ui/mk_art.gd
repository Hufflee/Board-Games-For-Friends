extends RefCounted
## Загрузка TTS-атласов и обложки: штатные импортированные ресурсы или исходные JPEG в рабочем checkout.

static var textures: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if textures.has(path):
		return textures[path]
	var value: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if value == null:
		var image := Image.load_from_file(path)
		if image == null:
			return null
		value = ImageTexture.create_from_image(image)
	textures[path] = value
	return value

static func illustration(sheet: int, cell: int) -> Texture2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture("res://games/machi_koro/art/sheets/sheet_%d_face.jpg" % sheet)
	var top := 280 if sheet == 16 else 340
	var height := 410 if sheet == 16 else (210 if sheet == 21 and cell == 6 else 260)
	atlas.region = Rect2((cell % 3) * 658 + 12, (cell / 3) * 1026 + top, 634, height)
	atlas.filter_clip = true
	return atlas

static func cover(part: String) -> Texture2D:
	if part in ["spine", "top"]:
		return texture("res://hub/covers/machi_koro_spine.svg")
	var atlas := AtlasTexture.new()
	atlas.atlas = texture("res://games/machi_koro/art/sheets/sheet_22_face.jpg")
	atlas.region = Rect2(0, 2052, 658, 1026)
	atlas.filter_clip = true
	return atlas
