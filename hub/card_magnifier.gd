extends CanvasLayer
## Лупа над картами (настройка «Просмотр карт: лупа»), не перехватывает мышь. Живёт в Prefs (все экраны).
## - Включается сразу при наведении на карту — без задержки обычного приближения: лупа сама находит под курсором
##   картинку карты (TextureRect карточных пропорций) или карту, которую стол передал через offer().
## - Карта рисуется из исходной текстуры в полном разрешении, а не растянутым снимком экрана.
## - «Лупа на Shift» (Prefs.magnifier_shift): пока зажат Shift, лупа работает в любом режиме просмотра и
##   не пропадает, если увести курсор с карты, — показывает последнюю карту.
var target: WeakRef
var glass: ColorRect
var _held := {}  # последняя показанная карта (для Shift): {tex, region, uv, uv_per_px, angle}
var _held_center := Vector2.ZERO
var _held_source := Vector2.ZERO

const ZOOM := 2.0
const CARD_SIDE := Vector2(28, 440)  # карта на экране: самая длинная сторона, px (поле Бродилки — не карта)


static func offer(owner: Node) -> bool:
	var prefs := owner.get_node_or_null("/root/Prefs")
	if prefs == null or not active(prefs):
		return false
	var hovered := owner.get_viewport().gui_get_hovered_control()
	if hovered == null:
		return true
	var lens := ensure(prefs)
	lens.target = weakref(hovered)
	return true


static func active(prefs: Node) -> bool:
	return prefs.card_preview_mode == "magnifier" or (bool(prefs.get("magnifier_shift")) and Input.is_key_pressed(KEY_SHIFT))


static func ensure(prefs: Node) -> Node:
	var lens := prefs.get_node_or_null("CardMagnifier")
	if lens == null:
		lens = load("res://hub/card_magnifier.gd").new()
		lens.name = "CardMagnifier"
		prefs.add_child(lens)
	return lens


func _ready() -> void:
	layer = 40
	glass = ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := ShaderMaterial.new()
	shader.shader = preload("res://hub/card_magnifier.gdshader")
	glass.material = shader
	glass.visible = false
	add_child(glass)


func _process(_delta: float) -> void:
	var prefs := get_parent()
	var shift_hold: bool = bool(prefs.get("magnifier_shift")) and Input.is_key_pressed(KEY_SHIFT)
	if not shift_hold:
		_held = {}
	if prefs.card_preview_mode != "magnifier" and not shift_hold:
		glass.visible = false
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var point: Vector2 = prefs.pointer_position
	var card := _card_at(point)
	if card.is_empty() and shift_hold and not _held.is_empty():
		# Shift зажат, курсор ушёл с карты — лупа остаётся на месте с последней картой.
		_show(_held, _held_center, _held_source, viewport_size)
		return
	if card.is_empty():
		glass.visible = false
		return
	var radius := _radius(viewport_size)
	var center := Vector2(clampf(point.x, radius + 8, viewport_size.x - radius - 8), clampf(point.y, radius + 56, viewport_size.y - radius - 8))
	if shift_hold:
		_held = card
		_held_center = center
		_held_source = point
	_show(card, center, point, viewport_size)


func _radius(viewport_size: Vector2) -> float:
	return minf(144, minf(viewport_size.x, viewport_size.y - 48) * 0.25)


func _show(card: Dictionary, center: Vector2, source: Vector2, viewport_size: Vector2) -> void:
	glass.visible = true
	glass.size = viewport_size
	var material := glass.material as ShaderMaterial
	material.set_shader_parameter("source_uv", source / viewport_size)
	material.set_shader_parameter("center_uv", center / viewport_size)
	material.set_shader_parameter("viewport_size", viewport_size)
	material.set_shader_parameter("radius", _radius(viewport_size))
	material.set_shader_parameter("zoom", ZOOM)
	var has_texture: bool = card.has("tex")
	material.set_shader_parameter("use_card", has_texture)
	if has_texture:
		material.set_shader_parameter("card_tex", card.tex)
		material.set_shader_parameter("card_region", card.region)
		material.set_shader_parameter("card_uv", card.uv)
		material.set_shader_parameter("card_uv_per_px", card.uv_per_px)
		material.set_shader_parameter("card_angle", card.angle)


## Карта под курсором: картинка из исходной текстуры или (если стол передал карту без картинки) — снимок экрана.
func _card_at(point: Vector2) -> Dictionary:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return {}
	var source: Control = target.get_ref() if target != null else null
	var offered := is_instance_valid(source) and source.is_visible_in_tree() and (hovered == source or source.is_ancestor_of(hovered))
	var roots: Array[Node] = [hovered]
	if offered:
		roots.append(source)
	var best := {}
	for root: Node in roots:
		var candidates: Array[Node] = [root]
		candidates.append_array(root.find_children("*", "TextureRect", true, false))
		for node: Node in candidates:
			if not node is TextureRect:
				continue
			var found := _sample(node as TextureRect, point, offered)
			if not found.is_empty():
				best = found  # последний в дереве — верхний на экране
		if not best.is_empty():
			return best
	return {"screen": true} if offered else {}


func _sample(rect: TextureRect, point: Vector2, offered: bool) -> Dictionary:
	var texture := rect.texture
	if texture == null or not rect.is_visible_in_tree() or rect.modulate.a < 0.2 or rect.self_modulate.a < 0.2:
		return {}
	var tex_size := texture.get_size()
	if tex_size.x < 1.0 or tex_size.y < 1.0:
		return {}
	var xform := rect.get_global_transform_with_canvas()
	var local := xform.affine_inverse() * point
	var draw_pos := Vector2.ZERO
	var draw_size := rect.size
	match rect.stretch_mode:
		TextureRect.STRETCH_KEEP:
			draw_size = tex_size
		TextureRect.STRETCH_KEEP_CENTERED:
			draw_size = tex_size
			draw_pos = (rect.size - tex_size) / 2.0
		TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var fit := minf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
			draw_size = tex_size * fit
			if rect.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
				draw_pos = (rect.size - draw_size) / 2.0
		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			var cover := maxf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
			draw_size = tex_size * cover
			draw_pos = (rect.size - draw_size) / 2.0
	if draw_size.x < 1.0 or draw_size.y < 1.0:
		return {}
	var uv := (local - draw_pos) / draw_size
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return {}
	if rect.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED and not Rect2(Vector2.ZERO, rect.size).has_point(local):
		return {}
	var scale := Vector2(xform.x.length(), xform.y.length())
	var screen_size := draw_size * scale
	if not offered:
		# Сама лупа ищет только карты: вытянутый прямоугольник разумного размера (не поле, не аватар).
		var long_side := maxf(screen_size.x, screen_size.y)
		var aspect := maxf(screen_size.x, screen_size.y) / maxf(1.0, minf(screen_size.x, screen_size.y))
		if long_side < CARD_SIDE.x or long_side > CARD_SIDE.y or aspect < 1.15 or aspect > 1.95:
			return {}
	var region := Vector4(0, 0, 1, 1)
	var base: Texture2D = texture
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		if atlas.atlas == null:
			return {}
		var full := atlas.atlas.get_size()
		region = Vector4(atlas.region.position.x / full.x, atlas.region.position.y / full.y, atlas.region.size.x / full.x, atlas.region.size.y / full.y)
		base = atlas.atlas
	if rect.flip_h:
		uv.x = 1.0 - uv.x
	if rect.flip_v:
		uv.y = 1.0 - uv.y
	return {"tex": base, "region": region, "uv": uv, "uv_per_px": Vector2.ONE / (screen_size * ZOOM), "angle": xform.get_rotation()}
