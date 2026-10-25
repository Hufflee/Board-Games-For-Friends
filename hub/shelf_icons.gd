class_name ShelfIcons
extends RefCounted
## Плоские иконки редактора и четырёх положений коробки, без зависимости от символьных шрифтов.
static var _cache: Dictionary = {}


static func icon(mode: int = -1) -> Texture2D:
	if _cache.has(mode):
		return _cache[mode]
	var shape: String
	if mode < 0:
		shape = '<path d="M5 22l2-7L20 2l6 6-13 13-8 1zM17 5l6 6M7 15l6 6"/>'
	elif mode == 0:
		shape = '<rect x="5" y="5" width="22" height="22" rx="2"/>'
	elif mode == 1:
		shape = '<rect x="10" y="3" width="12" height="26" rx="2"/>'
	elif mode == 3:
		shape = '<rect x="3" y="7" width="26" height="18" rx="2"/><path d="M6 10h20" stroke="#15242c"/>'
	else:
		shape = '<rect x="3" y="10" width="26" height="12" rx="2"/>'
	var svg := (
		(
			'<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><g fill="%s" stroke="#2ef2ff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">'
			% ("none" if mode < 0 else "#2ef2ff")
		)
		+ shape
		+ "</g></svg>"
	)
	var image := Image.new()
	image.load_svg_from_string(svg)
	var texture := ImageTexture.create_from_image(image)
	_cache[mode] = texture
	return texture
