extends RefCounted
## Ограничивает область настроек лобби размером окна и включает прокрутку при переполнении.


static func mount(parent: Control, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "LobbySettingsScroll"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		scroll.set_anchor(edge, content.get_anchor(edge))
		scroll.set_offset(edge, content.get_offset(edge))
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll
