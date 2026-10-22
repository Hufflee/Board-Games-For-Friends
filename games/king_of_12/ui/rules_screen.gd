extends Control
## Окно с памяткой по правилам и всеми картами.

const SUMMARY := """[b]Цель.[/b] Выиграть 2 раунда. Победитель раунда кладёт одну карту из руки под свой кубик; вторая такая карта — победа в игре.

[b]Начало раунда.[/b] Все бросают свои 12-гранные кубики. Кубик не перебрасывается до конца раунда.

[b]Розыгрыш.[/b]
1. Все одновременно и в закрытую выбирают карту из руки.
2. Одинаковые карты отменяются — без эффекта.
3. Эффекты оставшихся карт применяются. Торговцы — первыми, Оракул — последним. Леди отменяет эффекты всех остальных карт.
4. Значения кубиков сравниваются (грань + эффекты). Все равные значения отменяются.
5. Наибольшее значение — победитель (2 ПО), следующее — второе место (1 ПО).
6. Сыгранные карты уходят в сброс до конца раунда.

[b]Конец раунда[/b] — когда у игроков осталась одна карта в руке или у кого-то 8+ ПО. Карты возвращаются в руку, равные суммы ПО отменяются, наибольшая сумма выигрывает раунд.

[b]Важно.[/b] Только карты с символом [color=#5fb4ef]◆[/color] меняют грань кубика. Остальные меняют лишь значение на этот розыгрыш (оно может быть меньше 1 или больше 12). Противоположные грани в сумме дают 13."""


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var panel := K12UI.panel(Color(0.08, 0.055, 0.035, 0.97), 8, "double")
	margin.add_child(panel)
	var col := K12UI.vbox(10)
	panel.add_child(col)
	var head := K12UI.hbox()
	var title := K12UI.label("Правила «Дюжины короля»", K12UI.H1, K12UI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := K12UI.button("Закрыть", K12UI.BODY)
	close.pressed.connect(queue_free)
	head.add_child(close)
	col.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := K12UI.vbox(16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.text = SUMMARY
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 16)
	text.add_theme_color_override("default_color", K12UI.CREAM)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)

	body.add_child(K12UI.label("Карты", K12UI.BODY, K12UI.GOLD))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var all: Array = K12Cards.BASE.duplicate()
	all.append_array(K12Cards.PROMO)
	for c in all:
		grid.add_child(K12CardView.new(c))
	body.add_child(grid)
	body.add_child(K12UI.label("Коллекционер и Фавн — промокарты: в партию можно добавить только одну из них.", K12UI.CAP, K12UI.MUTED))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
