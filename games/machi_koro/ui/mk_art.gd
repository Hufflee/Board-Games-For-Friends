extends RefCounted
## Загрузка TTS-атласов и обложки: штатные импортированные ресурсы или исходные JPEG в рабочем checkout.

static var textures: Dictionary = {}
static var type_icons: Dictionary = {}

# Силуэты типов предприятий. Один цвет, чтобы значки читались и на мини-картах.
const TYPE_SHAPES := {
	"cow": '<path d="M6 7 2 5v5l4 2v5c0 5 12 5 12 0v-5l4-2V5l-4 2-2-2H8z"/><circle cx="9" cy="12" r="1" fill="#fff"/><circle cx="15" cy="12" r="1" fill="#fff"/><path d="M9 17h6" stroke="#fff" stroke-width="2" stroke-linecap="round"/>',
	"gear": '<path fill-rule="evenodd" d="m10 2-.7 3-2 .9L4.5 5 2.8 8l2.2 2v4l-2.2 2 1.7 3 2.8-.9 2 .9.7 3h4l.7-3 2-.9 2.8.9 1.7-3-2.2-2v-4l2.2-2-1.7-3-2.8.9-2-.9-.7-3zM12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8"/>',
	"crop": '<path d="M11 22v-5C5 17 3 14 3 10c4 0 7 2 8 5v-4C6 11 5 8 5 5c3 0 5 1 6 4V7c-2-3 0-5 1-6 2 2 3 4 1 6v2c1-3 3-4 6-4 0 3-1 6-6 6v4c1-3 4-5 8-5 0 4-2 7-8 7v5z"/>',
	"flower": '<path d="M10.5 15h3v8h-3zM12 20c-4 0-6-2-6-5 3 0 5 1 6 5"/><path fill-rule="evenodd" d="M12 3c4-5 8 0 6 3 5 0 5 6 1 7 1 4-4 6-7 3-3 3-8 1-7-3-4-1-4-7 1-7-2-3 2-8 6-3m0 4a3 3 0 1 0 0 6 3 3 0 0 0 0-6"/>',
	"boat": '<path d="M11 2h2v4h4v6H6V8h5zM2 14h20l-4 6H6zM2 21h20v2H2z"/>',
	"case": '<path fill-rule="evenodd" d="M8 6V4q0-2 2-2h4q2 0 2 2v2h4q2 0 2 2v12q0 2-2 2H4q-2 0-2-2V8q0-2 2-2zm2 0h4V4h-4zm-6 6v2h7v2h2v-2h7v-2z"/>',
	"factory": '<path fill-rule="evenodd" d="M2 22V5h4l1 9 6-4v4l8-4v12zm4-5v2h3v-2zm5 0v2h3v-2zm5 0v2h3v-2z"/>',
	"fruit": '<path d="M13 7c0-4 3-5 6-5 0 3-2 5-6 5m-1 2C6 4 1 9 3 15c1 5 4 8 9 6 5 2 8-1 9-6 2-6-3-11-9-6"/>',
	"shop": '<path fill-rule="evenodd" d="M3 3h18l2 6v3h-2v9H3v-9H1V9zm2 9v7h5v-7zm8 0v4h6v-4z"/>',
	"major": '<path fill-rule="evenodd" d="M2 22V9h6V2h9v7h5v13zm8-17v3h5V5zm0 5v3h5v-3zm0 6v4h5v-4z"/>',
	"cup": '<path fill-rule="evenodd" d="M3 5h15v2h2a3 3 0 0 1 0 6h-3c-1 3-3 5-7 5-5 0-7-4-7-9zm15 4v2h2a1 1 0 0 0 0-2zM2 19h20v2H2z"/>',
}

static func type_icon(kind: String) -> Texture2D:
	if not TYPE_SHAPES.has(kind):
		return null
	if not type_icons.has(kind):
		var image := Image.new()
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="#173c45">%s</g></svg>' % TYPE_SHAPES[kind]
		if image.load_svg_from_string(svg, 2.0) != OK:
			return null
		type_icons[kind] = ImageTexture.create_from_image(image)
	return type_icons[kind]

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
