class_name GLStack
extends Control
## Персонаж со всеми сыгранными на него прозрачными картами: портрет снизу, карты по порядку сверху —
## как настоящая стопка: видно только то, что не закрыто. Рядом — текущий счёт.

signal picked(index: int)
signal hovered(index: int, on: bool)

var index := -1  # номер персонажа в партии
var _images: Array[TextureRect] = []
var data: Dictionary = {}:  # {id, owner, stack, dead, removed, worth, icon}
	set(value):
		data = value
		if is_inside_tree():
			_sync_images()
var highlight := 0.0:  # подсветка цели (0…1)
	set(v):
		highlight = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var dim := false:
	set(v):
		dim = v
		queue_redraw()


const NAME_H := 18.0  # подпись с именем под картой


func _init(i: int, d: Dictionary, w: float) -> void:
	index = i
	data = d
	custom_minimum_size = Vector2(w, w * GLStyle.CARD.y / GLStyle.CARD.x + NAME_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	resized.connect(_sync_images)
	_sync_images()
	mouse_entered.connect(func(): hovered.emit(index, true))
	mouse_exited.connect(func(): hovered.emit(index, false))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(index)
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size - Vector2(0, NAME_H))
	# имя крупно под картой — на самой карте оно мелкое
	var nf := GLStyle.font("bold")
	var nm := str(data.get("name", ""))
	var nfs := 13
	while nfs > 8 and nf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > size.x + 6:
		nfs -= 1
	draw_string(nf, Vector2(0, r.end.y + NAME_H - 4), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x, nfs, GLStyle.BONE)
	if highlight > 0.01 or selected:
		var c := GLStyle.BLOOD_LIGHT if selected else Color(GLStyle.BONE, 0.85)
		draw_style_box(GLStyle.box(Color(c, 0.25 + 0.5 * highlight), 8, c, 3, 0.0), r.grow(5))
	if dim:
		draw_rect(r, Color(0, 0, 0, 0.45))
	# счёт — медальон у правого верхнего угла
	var w := int(data.get("worth", 0))
	var dead: bool = data.get("dead", false) and not data.get("undead", false)
	var rad := clampf(size.x * 0.15, 10.0, 19.0)
	var c2 := Vector2(size.x - rad - 3, rad + 3)
	draw_circle(c2, rad + 2, GLStyle.INK)
	draw_circle(c2, rad, GLStyle.BLOOD if w < 0 else (GLStyle.COAL_2 if w > 0 else GLStyle.MUTED))
	var f := GLStyle.font("bold")
	var txt := ("%+d" % w) if w != 0 else "0"
	var fs := int(rad * (0.95 if txt.length() <= 3 else 0.8))
	var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, c2 + Vector2(-ts.x * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GLStyle.BONE)
	if dead:
		# траурная лента внизу: «† R.I.P.» — подпись подгоняется под ширину карты
		var tf := GLStyle.font("title")
		var lab := "† Покойся с миром" if size.x >= 90 else "† R.I.P."
		var tfs := int(clampf(size.x * 0.12, 10, 18))
		while tfs > 8 and tf.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x > size.x * 0.92:
			tfs -= 1
		var tw := tf.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var band := Rect2(0, r.end.y - tfs * 1.7, size.x, tfs * 1.7)
		draw_rect(band, Color(GLStyle.COAL, 0.88))
		draw_line(band.position, band.position + Vector2(size.x, 0), GLStyle.BLOOD, 2.0)
		draw_string(tf, Vector2((size.x - tw) * 0.5, r.end.y - tfs * 0.5), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, GLStyle.BONE)


## Маска только на изображениях: подписи, медальоны и рамки остаются самостоятельными.
func _sync_images() -> void:
	for image: TextureRect in _images:
		remove_child(image)
		image.queue_free()
	_images.clear()
	var textures: Array[Texture2D] = [GLStyle.tex(str(data.get("img", "ch%d" % int(data.get("id", 0)))))]
	for card in data.get("stack", []):
		textures.append(GLStyle.card_tex(int(card)))
	for texture: Texture2D in textures:
		var image := TextureRect.new()
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_SCALE
		image.size = size - Vector2(0, NAME_H)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.show_behind_parent = true
		var corners := ShaderMaterial.new()
		corners.shader = preload("res://hub/card_corners.gdshader")
		image.material = corners
		add_child(image)
		_images.append(image)
