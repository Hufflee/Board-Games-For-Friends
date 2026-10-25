extends TextureRect
## Одобренный рисованный взрыв: оригинальная альфа, пропорции и горизонтальная надпись.
const ART := preload("res://games/stillion/art/bang_approved.png")


func _init() -> void:
	texture = ART
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size = Vector2(520, 260)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
