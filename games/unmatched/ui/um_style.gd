extends RefCounted
## Палитры утверждённого стайлборда. Панели, вкладки и кнопки используют общую рамку.

const TITLE := preload("res://games/colt_express/art/fonts/Oswald-Variable.ttf")
const BODY := preload("res://games/in_broad_strokes/art/fonts/Nunito-Variable.ttf")
const TOKENS := [Color("7db4db"), Color("b3cc8c"), Color("e4aa68"), Color("cf95c2")]
const COLORS := {
	"marmoreal": [
		["eee5d8", "f7e8e1", "542f49", "e9ced7", "c39676", "362632", "733c5d", "fff5ed", "efdbdd"],
		["272131", "39263b", "57314e", "261d32", "c18d7f", "fff0e8", "ecaac5", "341e2b", "493147"],
	],
	"sarpedon": [
		["dbc6a2", "f3e5c8", "19474a", "c8ded1", "c79359", "173a3a", "145862", "f6f3de", "dfdabb"],
		["17272e", "17393e", "145254", "102a30", "c89360", "f5eddb", "9ad8ca", "173739", "214951"],
	],
	"gardens": [
		["e7d2a7", "f5e7c9", "2b5068", "d3dfd7", "bd8e49", "213a4c", "345a70", "fff0d1", "e4dac1"],
		["253344", "253c53", "2b5068", "1b2c42", "ca9b55", "f8ebce", "edc378", "372b1e", "304756"],
	],
	"heorot": [
		["d7dcd4", "ecdfc9", "394b47", "d2d9cb", "b48450", "263630", "5f4937", "fff0d9", "d4c8b3"],
		["1d2f31", "293b3b", "40544d", "202f2f", "bb9662", "f2ead8", "e0b477", "372d23", "3b4d46"],
	],
	"raptor_paddock": [
		["dedbc0", "ede6ca", "4e5537", "d7dac0", "a88450", "333b28", "586244", "f9eed1", "d7c9a8"],
		["282e22", "353e2c", "4f5a3c", "292e21", "b99a63", "f1e8d0", "dac185", "35301f", "434d37"],
	],
	"venice": [
		["e0d7c5", "f1e3cc", "434f57", "d0d7d5", "ba8c53", "28353e", "465e6a", "fff1d9", "d9ceb9"],
		["202f39", "293e49", "445563", "202e38", "c09a66", "f6e9d4", "dfb27a", "392c23", "384c56"],
	],
}


static func palette(arena: String, dark: bool) -> Dictionary:
	var theme_id := preload("res://games/unmatched/ui/um_card_art.gd").arena_theme(arena)
	var colors: Array = COLORS[theme_id][int(dark)]
	var result := {}
	var keys := ["bg", "panel", "band", "well", "rim", "ink", "accent", "on", "track"]
	for i in keys.size():
		result[keys[i]] = Color(colors[i])
	return result


static func frame(fill: Color, edge: Color, padding: int = 8, cut: int = 6) -> StyleBoxTexture:
	var img := Image.create_empty(28, 28, false, Image.FORMAT_RGBA8)
	for y in 28:
		for x in 28:
			var dx := mini(x, 27 - x)
			var dy := mini(y, 27 - y)
			if dx + dy >= cut:
				img.set_pixel(x, y, edge if dx == 0 or dy == 0 or dx + dy == cut else fill)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, cut + 2)
		box.set_content_margin(side, padding)
	return box


static var _body_font: FontVariation


static func body_font() -> FontVariation:
	if _body_font == null:
		_body_font = FontVariation.new()
		_body_font.base_font = BODY
		var weight := TextServerManager.get_primary_interface().name_to_tag("wght")
		_body_font.variation_opentype = {weight: 600}
	return _body_font


static func make_theme(p: Dictionary, button_vertical_padding: int = 6) -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font()
	theme.default_font_size = 14
	for control_type: String in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit"]:
		theme.set_font("font", control_type, theme.default_font)
	theme.set_font("normal_font", "RichTextLabel", theme.default_font)
	theme.set_color("font_color", "Label", p.ink)
	var plate: Color = (p.band as Color).darkened(0.32)
	var brass: Color = p.rim
	var ink := Color("fff2e8")
	for type: String in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(state, type, ink)
		theme.set_color("font_disabled_color", type, ink.lerp(plate, 0.45))
		theme.set_stylebox("normal", type, stone(plate, brass, button_vertical_padding))
		theme.set_stylebox("hover", type, stone(plate.lightened(0.16), brass.lightened(0.16), button_vertical_padding))
		theme.set_stylebox("pressed", type, stone(plate.darkened(0.13), brass, button_vertical_padding))
		theme.set_stylebox("disabled", type, stone(plate, brass.darkened(0.56), button_vertical_padding))
		var focus := stone(Color.TRANSPARENT, brass.lightened(0.40), button_vertical_padding)
		focus.set_border_width_all(2)
		focus.shadow_size = 0
		theme.set_stylebox("focus", type, focus)
	theme.set_font("font", "PopupMenu", theme.default_font)
	theme.set_color("font_color", "PopupMenu", ink)
	theme.set_color("font_hover_color", "PopupMenu", ink)
	theme.set_stylebox("panel", "PopupMenu", frame(plate, brass, 5, 3))
	theme.set_stylebox("hover", "PopupMenu", stone(plate.lightened(0.16), brass, 4))
	theme.set_stylebox("panel", "PanelContainer", frame(p.panel, p.rim))
	return theme


static func stone(fill: Color, edge: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.border_width_bottom = 2
	box.set_corner_radius_all(3)
	box.shadow_color = Color(0.06, 0.04, 0.07, 0.30)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0.0, 2.0)
	box.set_content_margin(SIDE_TOP, padding)
	box.set_content_margin(SIDE_BOTTOM, padding)
	box.set_content_margin(SIDE_LEFT, 7)
	box.set_content_margin(SIDE_RIGHT, 7)
	return box


static func primary(button: Button, p: Dictionary) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color("fff2e8"))
	var fill: Color = (p.rim as Color).darkened(0.39)
	button.add_theme_stylebox_override("normal", stone(fill, p.rim, 6))
	button.add_theme_stylebox_override("hover", stone(fill.lightened(0.10), (p.rim as Color).lightened(0.09), 6))
	button.add_theme_stylebox_override("pressed", stone(fill.darkened(0.14), p.rim, 6))


static func card_back(p: Dictionary) -> Texture2D:
	var img := Image.create_empty(72, 100, false, Image.FORMAT_RGBA8)
	img.fill(p.band)
	for inset: int in [2, 6]:
		var width := 72 - 2 * inset
		var height := 100 - 2 * inset
		img.fill_rect(Rect2i(inset, inset, width, 1), p.rim)
		img.fill_rect(Rect2i(inset, 99 - inset, width, 1), p.rim)
		img.fill_rect(Rect2i(inset, inset, 1, height), p.rim)
		img.fill_rect(Rect2i(71 - inset, inset, 1, height), p.rim)
	for y in range(34, 67):
		var offset := 12 - roundi(float(absi(y - 50)) * 0.75)
		img.set_pixel(36 - offset, y, p.rim)
		img.set_pixel(36 + offset, y, p.rim)
	return ImageTexture.create_from_image(img)
