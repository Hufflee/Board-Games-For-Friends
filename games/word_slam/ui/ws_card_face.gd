class_name WSCardFace
extends Control
## Карточка слова рассказчика: пастельная «таблетка» цвета категории (как в оригинале:
## существительные — бежевые, глаголы — фиолетовые, прилагательные — салатовые, связки — голубые).

const SIZE := Vector2(108, 40)
const COLORS := {"noun": Color("efe0c4"), "verb": Color("dccff0"), "adj": Color("d6ecc4"), "other": Color("cfe6f2")}
const EDGES := {"noun": Color("c9a96e"), "verb": Color("9b80c8"), "adj": Color("86b65f"), "other": Color("6aa6c8")}

var id := ""
var pointed := 0.0:  # 0…1 — рассказчик указывает на карточку
	set(v):
		pointed = v
		queue_redraw()


func _init(card_id: String = "") -> void:
	id = card_id
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func category(card_id: String) -> String:
	return card_id.split(":")[0]


func _draw() -> void:
	draw_face(self, Rect2(Vector2.ZERO, size), id, pointed)


static func draw_face(ci: CanvasItem, r: Rect2, card_id: String, glow: float = 0.0) -> void:
	if card_id == "?":
		ci.draw_style_box(HCStyle.box(Color("e7e2da"), 10, Color("d3ccc0"), 1, HCStyle.SHADOW, 4), r)
		ci.draw_string(HCStyle.font("bold"), r.position + Vector2(0, r.size.y * 0.5 + 6), "?", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, HCStyle.MUTED)
		return
	var cat := category(card_id)
	var border: Color = EDGES[cat]
	if glow > 0.0:
		ci.draw_style_box(HCStyle.box(Color(1, 0.8, 0.3, 0.55 * glow), 14), r.grow(5 * glow))
	ci.draw_style_box(HCStyle.box(COLORS[cat], 10, border, 2 if glow <= 0.0 else 3, HCStyle.SHADOW, 6), r)
	var word := WSRules.card_word(card_id)
	var fs := 16 if word.length() <= 9 else (14 if word.length() <= 11 else 12)
	ci.draw_string(HCStyle.font("bold"), r.position + Vector2(0, r.size.y * 0.5 + fs * 0.36), word, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, HCStyle.INK_ART)
