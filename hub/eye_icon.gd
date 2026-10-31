class_name EyeIcon
extends RefCounted
## Общий значок «глазик» (рисуется линиями): «Посмотреть комнату» в хабе, «Показать карты» в покере.


## Глаз с центром center; k — масштаб (1 — как в хабе, ~20×12 px).
static func draw(canvas: CanvasItem, center: Vector2, color: Color, k: float = 1.0, width: float = 1.5) -> void:
	canvas.draw_arc(center + Vector2(0, 4) * k, 10 * k, PI * 1.16, PI * 1.84, 20, color, width, true)
	canvas.draw_arc(center + Vector2(0, -4) * k, 10 * k, PI * 0.16, PI * 0.84, 20, color, width, true)
	canvas.draw_circle(center, 3 * k, color)
