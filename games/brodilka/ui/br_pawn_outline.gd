## Мягкая светлая кромка старых персонажей, без изменения исходных PNG.
## BRStyle кеширует результат: меню, поле, список игроков и победитель получают одну текстуру.
extends RefCounted


static func make(source: Texture2D) -> Texture2D:
	var original := source.get_image()
	if original.is_compressed():
		original.decompress()
	original.convert(Image.FORMAT_RGBA8)
	original.clear_mipmaps()
	# Толщина зависит от высоты исходника, а не от размера портрета на экране.
	var radius := maxi(2, roundi(original.get_height() * 0.006))
	var pad := radius + 2
	var bounds := Rect2i(Vector2i.ZERO, original.get_size())
	var silhouette := Image.create(original.get_width(), original.get_height(), false, Image.FORMAT_RGBA8)
	var pixels := original.get_data()
	for offset in range(0, pixels.size(), 4):
		pixels[offset] = 248
		pixels[offset + 1] = 246
		pixels[offset + 2] = 237
	silhouette.set_data(original.get_width(), original.get_height(), false, Image.FORMAT_RGBA8, pixels)
	var result := Image.create(original.get_width() + pad * 2, original.get_height() + pad * 2, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	# Круглая кромка, а не квадратная рамка; прозрачный запас исключает срезы у краёв.
	for step in 16:
		var angle := TAU * step / 16.0
		var shift := Vector2i(roundi(cos(angle) * radius), roundi(sin(angle) * radius))
		result.blend_rect(silhouette, bounds, Vector2i(pad, pad) + shift)
	result.blend_rect(original, bounds, Vector2i(pad, pad))
	result.generate_mipmaps()
	return ImageTexture.create_from_image(result)
