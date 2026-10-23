## Данные «Большой бродилки»: карты Хорошо/Плохо, Тадам, Лавки Джо.
## Тексты — с листов в art/src (см. docs/TZ_brodilka.md, разделы 4–6). fx — ключ эффекта для BRRules.
class_name BRData
extends RefCounted

## Копий каждой карты в колодах.
const GOODBAD_COPIES := 1  # в оригинале каждая карта Хорошо/Плохо одна (мод TTS 2097352919)
const SHOP_COPIES := 2
const SHOP_MAX := 3
const SHOP_PRICE := 5
const TADAM_SLOTS := 3

## Двусторонние карты: good / bad — {text, fx, n?}.
const GOODBAD := [
	{good = {text = "Сбрось до 5 монет — за каждую 2 клетки вперёд.", fx = "pay_move", n = 5},
	 bad = {text = "Кубик: 1–3 — потеряй 5 монет; 4–6 — 10 клеток назад.", fx = "die_lose_or_back"}},
	{good = {text = "Забери любую карту Лавки у игрока, который тебя опережает.", fx = "steal_shop_ahead"},
	 bad = {text = "Все игроки теряют по 5 монет.", fx = "all_lose", n = 5}},
	{good = {text = "Кубик: 1–3 — получи 10 монет; 4–6 — 5 клеток вперёд.", fx = "die_coins_or_move"},
	 bad = {text = "5 клеток назад.", fx = "move", n = -5}},
	{good = {text = "Тащи 2 карты Лавки, одну положи бесплатно.", fx = "free_shop"},
	 bad = {text = "Назад до ближайшей красной клетки (нет — 3 назад).", fx = "back_to_red"}},
	{good = {text = "Выбери игрока, возьми у него 3 монеты.", fx = "take_from", n = 3},
	 bad = {text = "Плати по 3 монеты за каждую свою Лавку, неоплаченные сбрось.", fx = "shop_tax", n = 3}},
	{good = {text = "Положи по 1 своей монете на любые клетки. Остановившийся там пропускает ход.", fx = "coin_traps"},
	 bad = {text = "Все сбрасывают карты Лавки, кроме одной.", fx = "all_keep_one"}},
	{good = {text = "Вперёд до ближайшей зелёной клетки (нет — 3 вперёд).", fx = "fwd_to_green"},
	 bad = {text = "Все, кроме тебя, получают по 3 монеты.", fx = "others_gain", n = 3}},
	{good = {text = "Получи 5 монет.", fx = "gain", n = 5},
	 bad = {text = "Все, кроме тебя, получают по 3 монеты и идут на 3 вперёд.", fx = "others_gain_move", n = 3}},
	{good = {text = "5 клеток вперёд.", fx = "move", n = 5},
	 bad = {text = "Сбрось свою карту Лавки. Нет — назад до ближайшей красной.", fx = "lose_shop_or_red"}},
	{good = {text = "Получи 10 монет.", fx = "gain", n = 10},
	 bad = {text = "Выбери игрока, отдай ему 5 монет.", fx = "give_to", n = 5}},
	{good = {text = "3 клетки вперёд и 3 монеты.", fx = "move_gain", n = 3},
	 bad = {text = "Выбери игрока: оба пропускаете ход (вдвоём — только ты).", fx = "both_skip"}},
	{good = {text = "Сбрось 2 монеты — сделай ещё один ход.", fx = "pay_extra_turn", n = 2},
	 bad = {text = "Ты счастливчик! Ничего не происходит.", fx = "none"}},
	{good = {text = "Забери у каждого по 2 монеты.", fx = "take_all", n = 2},
	 bad = {text = "Выбери другого игрока, брось кубик — он идёт вперёд на выпавшее число.", fx = "target_push"}},
	{good = {text = "Выбери игрока, он теряет 5 монет.", fx = "target_lose", n = 5},
	 bad = {text = "Все остальные идут на 5 вперёд.", fx = "others_move", n = 5}},
	{good = {text = "Сбрось любую карту Лавки другого игрока.", fx = "burn_shop"},
	 bad = {text = "Выбери игрока: он делает два хода подряд.", fx = "target_double"}},
	{good = {text = "Сбрось сколько угодно монет — вперёд на столько же.", fx = "pay_move", n = 99},
	 bad = {text = "Выбери игрока, он получает 10 монет.", fx = "target_gain", n = 10}},
	{good = {text = "Выбери игрока, он тащит «Плохо».", fx = "target_bad"},
	 bad = {text = "Потеряй 5 монет.", fx = "lose", n = 5}},
	{good = {text = "Сбрось сколько угодно монет — остальные назад на столько же.", fx = "pay_push_all"},
	 bad = {text = "Тащи две «Плохо».", fx = "two_bad"}},
	{good = {text = "Получи 1 монету.", fx = "gain", n = 1},
	 bad = {text = "Ничего не происходит.", fx = "none"}},
]

## Картинки карт: art/cards/gb_<i>.webp («Плохо» внизу вверх ногами), tadam_<i>, shop_<id>, *_back.
## Нарезаны из листов мода Tabletop Simulator 2097352919 (только для личной игры).
static func gb_image(i: int) -> String:
	return "res://games/brodilka/art/cards/gb_%d.webp" % i


static func tadam_image(i: int) -> String:
	return "res://games/brodilka/art/cards/tadam_%d.webp" % i


static func shop_image(i: int) -> String:
	return "res://games/brodilka/art/cards/shop_%s.webp" % SHOP[i].id


## Тадам: when — когда проверяется (start/end — для последнего игрока, stop_red/stop_green, roll, pass, share).
const TADAM := [
	{text = "Последний игрок в начале своего хода тащит «Хорошо».", when = "start", fx = "draw_good"},
	{text = "Остановился на красной — тащи «Плохо».", when = "stop_red", fx = "draw_bad"},
	{text = "Остановился на красной — потеряй 3 монеты или 3 клетки назад.", when = "stop_red", fx = "lose_or_back", n = 3},
	{text = "Закончил ход на клетке с другим игроком — схватка!", when = "share", fx = "duel"},
	{text = "Последний игрок в начале своего хода получает 3 монеты.", when = "start", fx = "gain", n = 3},
	{text = "Последний игрок в конце своего хода идёт на 5 вперёд.", when = "end", fx = "move", n = 5},
	{text = "Обгоняешь кого-то — забираешь у него 3 монеты.", when = "pass", fx = "take", n = 3},
	{text = "Остановился на зелёной — получи 5 монет.", when = "stop_green", fx = "gain", n = 5},
	{text = "Последний игрок в конце своего хода бросает кубик и получает столько монет.", when = "end", fx = "die_gain"},
	{text = "Хотя бы на одном кубике 6 — пропусти ход («Жвачку» не касается).", when = "roll", fx = "six_skip"},
	{text = "Остановился на зелёной — тащи «Хорошо».", when = "stop_green", fx = "draw_good"},
	{text = "Остановился на красной — отдай всем по 2 монеты (вдвоём — 4).", when = "stop_red", fx = "give_all", n = 2},
	{text = "Остановился на зелёной — ходи ещё раз.", when = "stop_green", fx = "extra_turn"},
	{text = "Последний игрок в начале своего хода тащит бесплатную Лавку (если их меньше 3).", when = "start", fx = "free_shop"},
	{text = "Выпал дубль — ходи ещё раз.", when = "roll", fx = "double_extra"},
	{text = "Остановился на зелёной — 7 клеток вперёд.", when = "stop_green", fx = "move", n = 7},
]

## Лавка Джо: kind active (раз за ход, cost монет) / passive; copies — копий в колоде (по умолчанию SHOP_COPIES),
## once — одноразовая: сработала — в сброс.
const SHOP := [
	{id = "voodoo", name = "Вуду", kind = "active", cost = 3, text = "Игрок перед тобой тащит «Плохо»."},
	{id = "hook", name = "Крюк", kind = "active", cost = 3, text = "Переместись на клетку игрока в пределах 10 клеток впереди."},
	{id = "harpoon", name = "Гарпун", kind = "active", cost = 3, text = "Притяни игрока в пределах 10 клеток впереди на свою клетку."},
	{id = "fate", name = "Рука судьбы", kind = "active", cost = 0, text = "Выбранный игрок на 2 клетки назад (вдвоём и втроём — на 1)."},
	{id = "magnet", name = "Денежный магнит", kind = "passive", cost = 0, text = "Остановился на красной клетке — получи 5 монет."},
	{id = "grenade", name = "Граната", kind = "active", cost = 3, text = "Игрок перед тобой на 6 клеток назад."},
	{id = "rocket", name = "Ракета", kind = "active", cost = 3, text = "Ты на 5 клеток вперёд."},
	{id = "walkway", name = "Траволатор", kind = "passive", cost = 0, text = "Остановился на пустой клетке — 4 клетки вперёд."},
	{id = "clover", name = "Четырёхлистный клевер", kind = "passive", cost = 0, text = "Остановился на зелёной клетке — получи 4 монеты."},
	{id = "magic_die", name = "Волшебный куб", kind = "passive", cost = 0, text = "+1 к своему броску."},
	# --- 40 новых карт (docs/brodilka_new_cards.md): по 1 копии, картинка — art/items/<id>.png в рамке карты ---
	{id = "sling", name = "Рогатка", kind = "active", cost = 3, copies = 1, text = "Сбрось 3 монеты: игрок перед тобой — на 3 клетки назад."},
	{id = "swap", name = "Подменная шляпа", kind = "active", cost = 4, copies = 1, text = "Сбрось 4 монеты: поменяйся местами с игроком в пределах 6 клеток впереди."},
	{id = "lasso", name = "Лассо", kind = "active", cost = 3, copies = 1, text = "Сбрось 3 монеты: притяни на свою клетку игрока в пределах 10 клеток позади."},
	{id = "kite", name = "Воздушный змей", kind = "active", cost = 4, copies = 1, text = "Сбрось 4 монеты: вперёд до ближайшей зелёной клетки."},
	{id = "powder", name = "Бочка пороха", kind = "active", cost = 5, copies = 1, text = "Сбрось 5 монет: все в пределах 3 клеток от тебя — на 4 клетки назад."},
	{id = "fingers", name = "Ловкие пальцы", kind = "active", cost = 0, copies = 1, text = "Забери 3 монеты у игрока на твоей или соседней клетке."},
	{id = "map", name = "Карта сокровищ", kind = "active", cost = 4, copies = 1, text = "Сбрось 4 монеты: тащи карту «Хорошо»."},
	{id = "idol", name = "Проклятый идол", kind = "active", cost = 4, copies = 1, text = "Сбрось 4 монеты: выбранный игрок тащит «Плохо»."},
	{id = "trumpet", name = "Труба глашатая", kind = "active", cost = 2, copies = 1, text = "Сбрось 2 монеты: все остальные теряют по 2 монеты."},
	{id = "pony", name = "Пони", kind = "active", cost = 3, copies = 1, text = "Сбрось 3 монеты: на 4 клетки вперёд."},
	{id = "balloon", name = "Воздушный шар", kind = "active", cost = 6, copies = 1, text = "Сбрось 6 монет: на 8 клеток вперёд."},
	{id = "squid", name = "Каракатица", kind = "active", cost = 3, copies = 1, text = "Сбрось 3 монеты: игрок перед тобой пропускает ход."},
	{id = "bribe", name = "Взятка", kind = "active", cost = 5, copies = 1, text = "Сбрось 5 монет: тащи бесплатную карту Лавки."},
	{id = "rod", name = "Удочка", kind = "active", cost = 2, copies = 1, text = "Сбрось 2 монеты: укради карту Лавки у игрока в пределах 5 клеток впереди."},
	{id = "potion", name = "Зелье бодрости", kind = "active", cost = 4, copies = 1, text = "Сбрось 4 монеты: сделай ещё один ход."},
	{id = "jetpack", name = "Ранец-реактивник", kind = "active", cost = 5, copies = 1, text = "Сбрось 5 монет: на 6 клеток вперёд, клетка не срабатывает."},
	{id = "pocket_tp", name = "Карманный телепорт", kind = "active", cost = 4, copies = 1, text = "Сбрось 4 монеты: перенесись на ближайший телепорт впереди — и он сработает."},
	{id = "solvent", name = "Растворитель", kind = "active", cost = 0, copies = 1, once = true, text = "Один раз: если ты на Жвачке — отлипни и встань на финиш-сейф."},
	{id = "dice_bag", name = "Мешок кубиков", kind = "active", cost = 2, copies = 1, text = "Сбрось 2 монеты: брось кубик и получи столько монет."},
	{id = "magnet_big", name = "Большой магнит", kind = "active", cost = 5, copies = 1, text = "Сбрось 5 монет: все игроки в пределах 5 клеток — на твою клетку."},
	{id = "shield", name = "Щит", kind = "passive", cost = 0, copies = 1, once = true, text = "Следующая карта «Плохо» на тебя не действует. Потом сбрось."},
	{id = "boots", name = "Сапоги-скороходы", kind = "passive", cost = 0, copies = 1, text = "Выпало 1 — считай 3."},
	{id = "piggy", name = "Копилка", kind = "passive", cost = 0, copies = 1, text = "В начале своего хода получи 1 монету."},
	{id = "umbrella", name = "Зонтик", kind = "passive", cost = 0, copies = 1, text = "Смерч уносит тебя, только если хочешь: откупиться можно бесплатно."},
	{id = "anchor", name = "Якорь", kind = "passive", cost = 0, copies = 1, text = "Карты других игроков не двигают тебя назад."},
	{id = "lucky_coin", name = "Счастливая монетка", kind = "passive", cost = 0, copies = 1, text = "На открытом сундуке брось кубик: 5–6 — тащи «Хорошо» вместо «Плохо»."},
	{id = "backpack", name = "Рюкзак", kind = "passive", cost = 0, copies = 1, text = "Можешь держать 4 карты Лавки."},
	{id = "spyglass", name = "Подзорная труба", kind = "passive", cost = 0, copies = 1, text = "В Лавке Джо открываешь 3 карты вместо 2."},
	{id = "coupon", name = "Купон", kind = "passive", cost = 0, copies = 1, text = "Покупки в Лавке Джо стоят тебе 3 монеты."},
	{id = "horseshoe", name = "Подкова", kind = "passive", cost = 0, copies = 1, text = "Карты Тадам «на красной клетке» на тебя не действуют."},
	{id = "glove", name = "Боксёрская перчатка", kind = "passive", cost = 0, copies = 1, text = "В схватке +2 к твоему броску."},
	{id = "helmet", name = "Каска шахтёра", kind = "passive", cost = 0, copies = 1, text = "В Шахте «1» не пропускает ход — получи 10 монет."},
	{id = "nose", name = "Нюх кладоискателя", kind = "passive", cost = 0, copies = 1, text = "Остановился на закрытом сундуке — ещё 3 монеты."},
	{id = "parrot", name = "Попугай", kind = "passive", cost = 0, copies = 1, text = "Другой игрок покупает в Лавке Джо — получи 1 монету."},
	{id = "sandals", name = "Сандалии", kind = "passive", cost = 0, copies = 1, text = "Обгоняешь кого-то в свой ход — получи 1 монету за каждого."},
	{id = "tent", name = "Палатка", kind = "passive", cost = 0, copies = 1, text = "Пропускаешь ход — получи 4 монеты."},
	{id = "fan", name = "Веер", kind = "passive", cost = 0, copies = 1, text = "На светлой клетке бросаешь 2 кубика и выбираешь один."},
	{id = "charm", name = "Оберег", kind = "passive", cost = 0, copies = 1, text = "«Нееет!» отнимает у тебя только 3 монеты."},
	{id = "gold_tooth", name = "Золотой зуб", kind = "passive", cost = 0, copies = 1, text = "Дань: ты платишь не больше 2 монет."},
	{id = "elephant", name = "Слон в кармане", kind = "passive", cost = 0, copies = 1, text = "Ничья в схватке — победа твоя."},
]

## Названия клеток для журнала и подсказок.
const CELL_NAMES := {
	start = "Старт", empty = "Пустая клетка", chest_good = "Закрытый сундук", chest_bad = "Открытый сундук",
	shop = "Лавка Джо", tadam = "ТАДАМ", lucky = "Удачный расклад", tornado = "Смерч", tribute = "Дань",
	duel = "Схватка", bike = "Велосипед", mine = "Шахта", nooo = "Нееет!", luck_die = "Кубик удачи",
	gum = "Жвачка", cross = "Перекрёсток", finish = "Финиш-сейф",
	tele_y = "Жёлтый телепорт", tele_g = "Зелёный телепорт", tele_p = "Фиолетовый телепорт", tele_b = "Синий телепорт",
}


static func shop_index(id: String) -> int:
	for i in SHOP.size():
		if SHOP[i].id == id:
			return i
	return -1
