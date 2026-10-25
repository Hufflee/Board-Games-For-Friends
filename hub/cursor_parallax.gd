extends RefCounted
## Плавное смещение декоративного фона за курсором; интерфейс и поле остаются неподвижны.

static func step(control: Control, current: Vector2, delta: float, amplitude: float = 10.0) -> Vector2:
	var viewport_size := control.get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return current
	var normalized := control.get_viewport().get_mouse_position() / viewport_size * 2.0 - Vector2.ONE
	var target := -normalized.clamp(-Vector2.ONE, Vector2.ONE) * amplitude
	return current.lerp(target, 1.0 - exp(-maxf(delta, 0.0) * 4.0))
