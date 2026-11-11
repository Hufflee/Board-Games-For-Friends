extends "res://hub/poster_gif.gd"
## GIF для чата: те же правила разбора, что у плакатов (hub/poster_gif.gd), но без отказа на длинных
## и крупных гифках. Кадры уменьшаются до OUT_SIDE по длинной стороне, а если их слишком много —
## берётся каждый N-й (задержки пропущенных кадров складываются), чтобы уложиться в OUT_PIXELS.
## Возвращает картинки, а не текстуры: разбор идёт в фоновом потоке, текстуры создаёт главный.

const OUT_SIDE := 360
const OUT_PIXELS := 16_000_000
const CANVAS_SIDE := 2048
const FRAMES_TOTAL := 3000


## {"images": Array[Image], "delays": PackedFloat32Array} или пустой словарь, если файл не разобрать.
static func frames(bytes: PackedByteArray) -> Dictionary:
	if not matches(bytes):
		return {}
	var reader := new()
	reader._data = bytes
	return reader._frames()


## Сколько кадров в файле (быстрый проход без распаковки).
func _count() -> int:
	_at = 13
	_palette(_data[10])
	var total := 0
	while _at >= 0 and _at < _data.size():
		var tag := _data[_at]
		_at += 1
		if tag == 0x3b:
			break
		if tag == 0x21:
			_at += 1
			_blocks()
			continue
		if tag != 0x2c or _at + 9 > _data.size():
			break
		var flags := _data[_at + 8]
		_at += 9
		if (flags & 128) != 0:
			_at += 3 * (2 << (flags & 7))
		_at += 1
		_blocks()
		total += 1
	return total


func _frames() -> Dictionary:
	var width := _data.decode_u16(6)
	var height := _data.decode_u16(8)
	if width <= 0 or height <= 0 or width > CANVAS_SIDE or height > CANVAS_SIDE:
		return {}
	var total := _count()
	if total <= 0 or total > FRAMES_TOTAL:
		return {}
	var ratio := minf(1.0, float(OUT_SIDE) / maxi(width, height))
	var out_w := maxi(1, roundi(width * ratio))
	var out_h := maxi(1, roundi(height * ratio))
	var keep := clampi(OUT_PIXELS / (out_w * out_h), 8, 400)
	var step := ceili(float(total) / keep)
	_at = 13
	var global_palette := _palette(_data[10])
	var background := _color(global_palette, _data[11])
	var canvas := PackedByteArray()
	canvas.resize(width * height * 4)
	var images: Array[Image] = []
	var delays := PackedFloat32Array()
	var delay := 0.1
	var transparent := -1
	var disposal := 0
	var index := 0
	while _at >= 0 and _at < _data.size():
		var tag := _data[_at]
		_at += 1
		if tag == 0x3b:
			break
		if tag == 0x21:
			if _at >= _data.size():
				break
			var label := _data[_at]
			_at += 1
			var blocks := _blocks()
			if _at < 0:
				break
			if label == 0xf9 and blocks.size() == 4:
				disposal = (blocks[0] >> 2) & 7
				transparent = blocks[3] if (blocks[0] & 1) != 0 else -1
				var ticks := blocks.decode_u16(1)
				delay = float(ticks) / 100.0 if ticks >= 2 else 0.1
			continue
		if tag != 0x2c or _at + 9 > _data.size():
			break
		var rect := Rect2i(_data.decode_u16(_at), _data.decode_u16(_at + 2), _data.decode_u16(_at + 4), _data.decode_u16(_at + 6))
		var flags := _data[_at + 8]
		_at += 9
		if not rect.has_area() or rect.end.x > width or rect.end.y > height:
			break
		var palette := _palette(flags) if (flags & 128) != 0 else global_palette
		if palette.is_empty() or _at >= _data.size():
			break
		var code_size := _data[_at]
		_at += 1
		var compressed := _blocks()
		if _at < 0:
			break
		var pixels := _lzw(compressed, code_size, rect.get_area())
		if pixels.is_empty():
			break
		if index == 0 and transparent < 0 and background != 0:
			_fill(canvas, width, Rect2i(0, 0, width, height), background)
		var previous := canvas.duplicate() if disposal == 3 else PackedByteArray()
		var rows := _row_order(rect.size.y, (flags & 64) != 0)
		var broken := false
		for row in rows.size():
			var target := ((rect.position.y + rows[row]) * width + rect.position.x) * 4
			for x in rect.size.x:
				var color_index := pixels[row * rect.size.x + x]
				if color_index == transparent:
					continue
				if color_index >= palette.size():
					broken = true
					break
				canvas.encode_u32(target + x * 4, palette[color_index])
			if broken:
				break
		if broken:
			break
		if index % step == 0:
			var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, canvas)
			if ratio < 1.0:
				image.resize(out_w, out_h, Image.INTERPOLATE_BILINEAR)
			images.append(image)
			delays.append(delay)
		elif not delays.is_empty():
			delays[delays.size() - 1] += delay
		index += 1
		if disposal == 2:
			_fill(canvas, width, rect, 0 if transparent >= 0 else background)
		elif disposal == 3:
			canvas = previous
		delay = 0.1
		transparent = -1
		disposal = 0
	if images.is_empty():
		return {}
	return {"images": images, "delays": delays}
