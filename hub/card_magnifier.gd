extends CanvasLayer
## Лупа увеличивает участок экрана вместе с окружением карты, не перехватывая мышь.
var target: WeakRef
var glass: ColorRect

static func offer(owner: Node) -> bool:
	var prefs := owner.get_node_or_null("/root/Prefs")
	if prefs == null or prefs.card_preview_mode != "magnifier":
		return false
	var hovered := owner.get_viewport().gui_get_hovered_control()
	if hovered == null:
		return true
	var lens := prefs.get_node_or_null("CardMagnifier")
	if lens == null:
		lens = load("res://hub/card_magnifier.gd").new()
		lens.name = "CardMagnifier"
		prefs.add_child(lens)
	lens.target = weakref(hovered)
	return true

func _ready() -> void:
	layer = 40
	glass = ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := ShaderMaterial.new()
	shader.shader = preload("res://hub/card_magnifier.gdshader")
	glass.material = shader
	add_child(glass)

func _process(_delta: float) -> void:
	var source: Control = target.get_ref() if target != null else null
	var hovered := get_viewport().gui_get_hovered_control()
	var prefs := get_parent()
	glass.visible = prefs.card_preview_mode == "magnifier" and is_instance_valid(source) and source.is_visible_in_tree() and hovered != null and (hovered == source or source.is_ancestor_of(hovered))
	if not glass.visible:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var point: Vector2 = prefs.pointer_position
	var radius := minf(144, minf(viewport_size.x, viewport_size.y - 48) * 0.25)
	var center := Vector2(clampf(point.x, radius + 8, viewport_size.x - radius - 8), clampf(point.y, radius + 56, viewport_size.y - radius - 8))
	glass.size = viewport_size
	glass.material.set_shader_parameter("source_uv", point / viewport_size)
	glass.material.set_shader_parameter("center_uv", center / viewport_size)
	glass.material.set_shader_parameter("viewport_size", viewport_size)
	glass.material.set_shader_parameter("radius", radius)
