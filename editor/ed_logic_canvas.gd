extends Control
## Масштаб логических цепочек: контейнер прокрутки получает реальный размер увеличенного содержимого.
var content: VBoxContainer
var zoom := 1.0
var _scheduled := false

func setup(chains: VBoxContainer, scale_value: float) -> void:
	name = "LogicZoomCanvas"
	size_flags_horizontal = SIZE_EXPAND_FILL
	content = chains
	content.name = "LogicChainsContent"
	zoom = clampf(scale_value, 0.6, 1.5)
	add_child(content)
	content.minimum_size_changed.connect(_schedule)
	resized.connect(_schedule)
	_schedule()

func _schedule() -> void:
	if _scheduled:
		return
	_scheduled = true
	_sync.call_deferred()

func _sync() -> void:
	_scheduled = false
	if not is_inside_tree() or not is_instance_valid(content):
		return
	var scroll := get_parent() as ScrollContainer
	var available := maxf(64, scroll.size.x - scroll.get_v_scroll_bar().size.x)
	var minimum := content.get_combined_minimum_size()
	content.scale = Vector2.ONE * zoom
	content.position = Vector2.ZERO
	content.size = Vector2(maxf(minimum.x, available / zoom), minimum.y)
	custom_minimum_size = content.get_combined_minimum_size() * zoom
