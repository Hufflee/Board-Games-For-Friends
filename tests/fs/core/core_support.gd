extends RefCounted
## card_support.json покрывает все карты манифеста, статусы известны, у каждой карты есть подсказка.
const FSCheck = preload("res://tests/fs/fs_check.gd")
const Support = preload("res://games/four_souls/logic/fs_support.gd")

func run(t: FSCheck) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://games/four_souls/art/card_support.json"))
	var missing := 0
	var bad := 0
	for card: Dictionary in FSData.data().cards:
		var id := int(card.id)
		var e: Dictionary = Support.entry(id)
		if not data.cards.has(str(id)):
			missing += 1
		if not str(e.get("status", "")) in ["auto", "partial", "manual"] or str(e.get("hint", "")).is_empty():
			bad += 1
	t.equal(missing, 0, "Карт без записи в card_support.json")
	t.equal(bad, 0, "Карт с неизвестным статусом или без подсказки")
	t.equal(Support.status(709), "auto", "Проклятие алчности автоматизировано")
	t.equal(Support.status(127), "auto", "Волшебник: полный текст покрыт пакетом12")
	t.equal(Support.status(121), "auto", "Хвост Гаппи: закрытый кейс не становится ручным после генерации")
	t.equal(Support.status(675), "auto", "Закрытая автоматика монет не становится ручной после генерации")
	t.equal(Support.status(899), "auto", "Классический кубик: два кубика и выбор другого игрока автоматизированы (пакет28)")
	t.equal(Support.status(7), "auto", "Друг автоматически считает чужие души и превращается")
	t.equal(Support.status(8), "auto", "Карма выдаёт ресурсы после выбора получателей и их предметов")
	t.equal(Support.status(243), "auto", "Сундук автоматически заменяет обычное уничтожение")
	t.equal(Support.status(6), "auto", "Динамит: активная таблица и перезарядка покрыты пакетом10")
	t.equal(Support.status(893), "auto", "Мёртвый груз: отмена срабатывающей способности выбирается кнопкой (пакет28)")
	t.equal(Support.status(518), "auto", "У Пакета проверено замещение уничтожения")
	t.equal(Support.status(867), "auto", "У Гиперкоагуляции проверены оба события жетонов")
