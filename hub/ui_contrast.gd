## Контраст текста и фона по относительной яркости sRGB.
class_name UIContrast
extends RefCounted


static func ratio(fg: Color, bg: Color) -> float:
	var a := _luminance(bg.blend(fg))
	var b := _luminance(bg)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


static func pick(bg: Color, candidates: Array[Color], need := 4.5) -> Color:
	var best := bg
	var best_ratio := 0.0
	for candidate in candidates:
		var score := ratio(candidate, bg)
		if score >= need:
			return candidate
		if score > best_ratio:
			best = candidate
			best_ratio = score
	return best


static func _luminance(color: Color) -> float:
	return 0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b)


static func _linear(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
