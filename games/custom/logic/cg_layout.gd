extends RefCounted
## Адаптация базового стола1280×672 под свободное место окна; верхняя полоса обрабатывается отдельно.
const BASE := Vector2(1280, 672)
const X := ["left", "center", "right", "stretch"]
const Y := ["top", "center", "bottom", "stretch"]

static func adaptive(layout: Dictionary) -> bool:
	for screen: Dictionary in layout.get("screens", []):
		for item: Dictionary in screen.get("items", []):
			if item.get("anchors") is Dictionary:
				return true
	return false

static func rect(base: Rect2, item: Dictionary, area: Vector2) -> Rect2:
	var anchors: Dictionary = item.get("anchors", {})
	var extra := (area - BASE).max(Vector2.ZERO)
	for axis: int in 2:
		var mode := str(anchors.get("x" if axis == 0 else "y", "center" if axis == 0 else "top"))
		if mode == "stretch":
			base.size[axis] += extra[axis]
		elif mode == "center":
			base.position[axis] += extra[axis] * 0.5
		elif mode in ["right", "bottom"]:
			base.position[axis] += extra[axis]
	return base
