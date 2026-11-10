extends Control
## Печатные цифры монстра поверх изображения. Атлас собирается tools/make_fs_stat_overlays.py.
## Хост передаёт фактические hp, dc и at. Изображение исходной карты не меняется.

const ART := "res://games/four_souls/art/monster_stats"
const STATS := ["hp", "dc", "at"]
const EASIER := Color("#16592f")
const HARDER := Color("#932431")
const EASIER_ON_DARK := Color("#8cd49d")
const HARDER_ON_DARK := Color("#ff9b9f")

static var _atlas: Texture2D
static var _layout: Dictionary = {}
var _card_size: Vector2
var _monster: Dictionary


func _init(monster: Dictionary, card_size: Vector2) -> void:
	_card_size = card_size
	_monster = monster


func _ready() -> void:
	name = "MonsterStats"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	if _atlas == null:
		_layout = JSON.parse_string(FileAccess.get_file_as_string(ART + ".json"))
		var path := ART + ".png"
		if ResourceLoader.exists(path):
			_atlas = load(path)
		else:
			_atlas = ImageTexture.create_from_image(Image.load_from_file(path))


func set_monster(monster: Dictionary) -> void:
	_monster = monster
	queue_redraw()


func _draw() -> void:
	if _atlas == null or _monster.is_empty() or _card_size.x <= 0 or _card_size.y <= 0:
		return
	var id := int(_monster.id)
	var tiles: Array = _layout.cards.get(str(id), [])
	if tiles.is_empty():
		return
	# Та же вписанная область, что и у TextureRect.STRETCH_KEEP_ASPECT_CENTERED.
	var factor := minf(size.x / _card_size.x, size.y / _card_size.y)
	draw_set_transform((size - _card_size * factor) * 0.5, 0.0, Vector2.ONE * factor)
	var on_dark := id in [913, 914]
	for stat in STATS.size():
		var printed := FSData.stat(id, STATS[stat], 0)
		var actual := int(_monster.get(STATS[stat], printed))
		# Перечёркнутый порог на неатакуемой карте обозначает отсутствие броска.
		if stat == 1 and printed == 0 and bool(_monster.get("untargetable", false)):
			continue
		if actual == printed:
			continue
		var tile: Array = tiles[stat]
		var patch := _rect(tile)
		var area := Rect2(Vector2(float(tile[4]), float(tile[5])), patch.size)
		var easier := actual < printed
		var ink := (EASIER_ON_DARK if easier else HARDER_ON_DARK) if on_dark else (EASIER if easier else HARDER)
		draw_texture_rect_region(_atlas, area, patch)
		_draw_value(area, actual, stat == 1 and actual > 0 and actual < 6, ink)
		_draw_indicator(area, easier, ink)


func _draw_value(area: Rect2, value: int, has_plus: bool, ink: Color) -> void:
	var height := minf(45.0, area.size.y - 8.0)
	var sprites: Array[Rect2] = []
	var widths: Array[float] = []
	var text := str(maxi(0, value))
	if has_plus:
		text += "+"
	for symbol in text:
		var glyph_index := 10 if symbol == "+" else int(symbol)
		var sprite := _rect(_layout.glyphs[glyph_index])
		var glyph_height := height * 0.44 if glyph_index == 10 else height
		sprites.append(sprite)
		widths.append(sprite.size.x * glyph_height / sprite.size.y)
	var gap := height * 0.035
	var width := float(widths.reduce(func(total, next): return total + next, 0.0)) + gap * (widths.size() - 1)
	var shrink := minf(1.0, (area.size.x - 4.0) / width)
	var center := area.get_center()
	var x := center.x - width * shrink * 0.5
	var baseline := center.y + height * shrink * 0.5
	for index in sprites.size():
		var glyph_width := widths[index] * shrink
		var glyph_height := sprites[index].size.y * glyph_width / sprites[index].size.x
		var dest := Rect2(x, baseline - glyph_height, glyph_width, glyph_height)
		draw_texture_rect_region(_atlas, dest, sprites[index], ink)
		x += glyph_width + gap * shrink


func _draw_indicator(area: Rect2, easier: bool, ink: Color) -> void:
	var radius := minf(5.0, area.size.y * 0.1)
	var center := area.position + Vector2(area.size.x - radius * 1.15, radius * 1.15)
	var direction := 1.0 if easier else -1.0
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-radius, -radius * direction),
		center + Vector2(radius, -radius * direction),
		center + Vector2(0, radius * direction),
	]), ink)


func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
