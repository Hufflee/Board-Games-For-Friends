extends RefCounted
## Декодирование GIF87a/89a для плакатов. Поддерживает палитры, прозрачность,
## чересстрочные кадры и восстановление кадра. Лимиты ограничивают память при получении по сети.

const MAX_SIDE := 1024
const MAX_FRAMES := 256
const MAX_FRAME_PIXELS := 16_000_000

var _data: PackedByteArray
var _at := 0


static func matches(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 13 and bytes.slice(0, 6).get_string_from_ascii() in ["GIF87a", "GIF89a"]


static func texture(bytes: PackedByteArray) -> Resource:
	if not matches(bytes):
		return null
	var reader := new()
	reader._data = bytes
	return reader._decode()


func _decode() -> Resource:
	var width := _data.decode_u16(6)
	var height := _data.decode_u16(8)
	if width <= 0 or height <= 0 or width > MAX_SIDE or height > MAX_SIDE:
		return null
	_at = 13
	var global_palette := _palette(_data[10])
	if (_data[10] & 128) != 0 and global_palette.is_empty():
		return null
	var background := _color(global_palette, _data[11])
	var canvas := PackedByteArray()
	canvas.resize(width * height * 4)
	var frames: Array[ImageTexture] = []
	var delays := PackedFloat32Array()
	var delay := 0.1
	var transparent := -1
	var disposal := 0
	while _at < _data.size():
		var tag := _data[_at]
		_at += 1
		if tag == 0x3b:
			return _animation(frames, delays)
		if tag == 0x21:
			if _at >= _data.size():
				return null
			var label := _data[_at]
			_at += 1
			var blocks := _blocks()
			if _at < 0:
				return null
			if label == 0xf9:
				if blocks.size() != 4:
					return null
				disposal = (blocks[0] >> 2) & 7
				transparent = blocks[3] if (blocks[0] & 1) != 0 else -1
				var ticks := blocks.decode_u16(1)
				delay = float(ticks) / 100.0 if ticks >= 2 else 0.1
			continue
		if tag != 0x2c or _at + 9 > _data.size() or frames.size() >= MAX_FRAMES:
			return null
		if (frames.size() + 1) * width * height > MAX_FRAME_PIXELS:
			return null
		var rect := Rect2i(_data.decode_u16(_at), _data.decode_u16(_at + 2),
			_data.decode_u16(_at + 4), _data.decode_u16(_at + 6))
		var flags := _data[_at + 8]
		_at += 9
		if not rect.has_area() or rect.end.x > width or rect.end.y > height:
			return null
		var palette := _palette(flags) if (flags & 128) != 0 else global_palette
		if palette.is_empty() or _at >= _data.size():
			return null
		var code_size := _data[_at]
		_at += 1
		var compressed := _blocks()
		if _at < 0:
			return null
		var pixels := _lzw(compressed, code_size, rect.get_area())
		if pixels.is_empty():
			return null
		if frames.is_empty() and transparent < 0 and background != 0:
			_fill(canvas, width, Rect2i(0, 0, width, height), background)
		var previous := canvas.duplicate() if disposal == 3 else PackedByteArray()
		var rows := _row_order(rect.size.y, (flags & 64) != 0)
		for row in rows.size():
			var target := ((rect.position.y + rows[row]) * width + rect.position.x) * 4
			for x in rect.size.x:
				var index := pixels[row * rect.size.x + x]
				if index == transparent:
					continue
				if index >= palette.size():
					return null
				canvas.encode_u32(target + x * 4, palette[index])
		var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, canvas)
		image.generate_mipmaps()
		frames.append(ImageTexture.create_from_image(image))
		delays.append(delay)
		if disposal == 2:
			_fill(canvas, width, rect, 0 if transparent >= 0 else background)
		elif disposal == 3:
			canvas = previous
		delay = 0.1
		transparent = -1
		disposal = 0
	return null


func _palette(flags: int) -> PackedInt64Array:
	var colors := PackedInt64Array()
	if (flags & 128) == 0:
		return colors
	var count := 2 << (flags & 7)
	if _at + count * 3 > _data.size():
		return colors
	for i in count:
		colors.append(_data[_at] | (_data[_at + 1] << 8) | (_data[_at + 2] << 16) | 0xff000000)
		_at += 3
	return colors


func _blocks() -> PackedByteArray:
	var out := PackedByteArray()
	while _at < _data.size():
		var count := _data[_at]
		_at += 1
		if count == 0:
			return out
		if _at + count > _data.size():
			break
		out.append_array(_data.slice(_at, _at + count))
		_at += count
	_at = -1
	return PackedByteArray()


static func _color(palette: PackedInt64Array, index: int) -> int:
	return palette[index] if index < palette.size() else 0


static func _fill(canvas: PackedByteArray, width: int, rect: Rect2i, color: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			canvas.encode_u32((y * width + x) * 4, color)


static func _row_order(height: int, interlaced: bool) -> PackedInt32Array:
	var rows := PackedInt32Array()
	if interlaced:
		for pass_info: Vector2i in [Vector2i(0, 8), Vector2i(4, 8), Vector2i(2, 4), Vector2i(1, 2)]:
			for y in range(pass_info.x, height, pass_info.y):
				rows.append(y)
	else:
		for y in height:
			rows.append(y)
	return rows


static func _animation(frames: Array[ImageTexture], delays: PackedFloat32Array) -> Resource:
	if frames.is_empty():
		return null
	if frames.size() == 1:
		return frames[0]
	var animation := SpriteFrames.new()
	animation.set_animation_speed(&"default", 1.0)
	for i in frames.size():
		animation.add_frame(&"default", frames[i], delays[i])
	return animation


## Словарь хранит префикс и последний индекс цвета, а не целую строку на каждый код.
static func _lzw(data: PackedByteArray, minimum: int, count: int) -> PackedByteArray:
	if minimum < 2 or minimum > 8:
		return PackedByteArray()
	var clear := 1 << minimum
	var stop := clear + 1
	var available := stop + 1
	var code_size := minimum + 1
	var previous := -1
	var first := 0
	var prefix := PackedInt32Array()
	prefix.resize(4096)
	var suffix := PackedByteArray()
	suffix.resize(4096)
	var reversed := PackedByteArray()
	reversed.resize(4096)
	var output := PackedByteArray()
	output.resize(count)
	var position := 0
	var input := 0
	var bits := 0
	var buffer := 0
	while true:
		while bits < code_size:
			if input >= data.size():
				return PackedByteArray()
			buffer |= data[input] << bits
			input += 1
			bits += 8
		var code := buffer & ((1 << code_size) - 1)
		buffer >>= code_size
		bits -= code_size
		if code == stop:
			return output if position == count else PackedByteArray()
		if code == clear:
			available = stop + 1
			code_size = minimum + 1
			previous = -1
			continue
		var current := code
		var length := 0
		if code >= available:
			if code != available or previous < 0:
				return PackedByteArray()
			reversed[length] = first
			length += 1
			code = previous
		while code > stop:
			reversed[length] = suffix[code]
			length += 1
			code = prefix[code]
		if code >= clear or position + length >= count:
			return PackedByteArray()
		first = code
		output[position] = first
		position += 1
		while length > 0:
			length -= 1
			output[position] = reversed[length]
			position += 1
		if previous >= 0 and available < 4096:
			prefix[available] = previous
			suffix[available] = first
			available += 1
			if available == (1 << code_size) and code_size < 12:
				code_size += 1
		previous = current
	return PackedByteArray()
