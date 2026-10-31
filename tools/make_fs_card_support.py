# Four Souls: собирает games/four_souls/art/card_support.json — статус автоматизации каждой карты.
# Источники: таблицы раздела 2 docs/FS_BUGS.md + список AUTO ниже (что автоматизировано после 31.10).
# Запуск из корня проекта: python tools/make_fs_card_support.py
import json, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
manifest = json.loads((ROOT / "games/four_souls/art/manifest.json").read_text(encoding="utf-8"))
bugs = (ROOT / "docs/FS_BUGS.md").read_text(encoding="utf-8")

# Автоматизировано пакетами этапа 3 (31.10): карта → что делает движок (остальное по тексту — вручную).
AUTO = {
    707: "1 урон в начале хода — автоматически", 709: "−4¢ в конце хода — автоматически",
    723: "Ход нельзя закончить, пока атака возможна", 724: "Конец хода: всё деактивируется автоматически",
    729: "Лимит руки 2 — автоматически", 736: "Конец хода: сброс X лута (выбор) и X¢ — автоматически",
    708: "Конец хода: сброс двух лута (выбор) — автоматически",
    49: "Поиск бомб при получении и бомба из сброса в начале хода — автоматически",
    67: "Поиск пилюль при получении и пилюля из сброса в начале хода — автоматически",
    120: "Перезарядка при одинаковом результате дважды подряд — автоматически",
    118: "Аура +1 защиты и урон остальным монстрам — автоматически",
    143: "+2 атаки и аура +1 защиты — автоматически", 75: "Аура −X защиты — автоматически",
    503: "Первое убийство за ход: лечение и доп. атака — автоматически",
    91: "Скидка 4¢ — автоматически", 889: "Скидка 3¢ — автоматически",
    765: "Всем монстрам +1 защита — автоматически", 818: "Всем монстрам +1 атака — автоматически",
    797: "Всем монстрам +1 здоровье (при появлении и восстановлении) — автоматически",
    777: "На смерть игрока остальные берут 1 лут — автоматически", 802: "Конец хода: персонаж повёрнут — автоматически",
    816: "Конец хода без покупки: сброс всей руки — автоматически", 809: "Обязательная атака верха колоды — автоматически",
    781: "Обязательная атака и +1 атака — автоматически", 782: "Отстающим по душам покупка бесплатна — автоматически",
}
PARTIAL = {
    127: "Аура +1 защиты — автоматически. Урон другой цели при боевом уроне — вручную: «Урон монстру» / «Нанести урон игроку».",
    194: "Аура +1 защиты — автоматически. Перед штрафом смерти передать предмет — вручную: «Передать свой предмет».",
    62: "Магазин +2 при получении — автоматически. Награда за чужую покупку — вручную.",
    706: "При смерти автоматически уничтожается самая дешёвая душа (последняя при равенстве); если нужна другая — поправьте вручную.",
    144: "+3 урона на шестёрке — автоматически. Единица: завершить ход вручную («Отменить атаку», затем «Конец хода»).",
}

def rows():
    out = {}
    for line in bugs.split("\n"):
        m = re.match(r"^\| (\d+) \| (.+?) \| (.+?) \| (.+?) \|$", line)
        if not m or int(m.group(1)) < 1 or int(m.group(1)) > 913:
            continue
        # строки раздела 1 (баги 1–9) имеют класс в 2-й колонке — отбрасываем
        if re.fullmatch(r"[A-F]", m.group(2).strip()):
            continue
        out[int(m.group(1))] = {"expect": m.group(2).strip(), "limit": m.group(3).strip(), "status": m.group(4).strip()}
    return out

def automated_ids():
    """id из таблиц автоматики fs_passives.gd / fs_passive_rules.gd (ключи словарей и список перезарядки)."""
    ids = set()
    passives = (ROOT / "games/four_souls/logic/fs_passives.gd").read_text(encoding="utf-8")
    simple = (ROOT / "games/four_souls/logic/fs_passive_rules.gd").read_text(encoding="utf-8")
    for name in ("ATTACK", "HEALTH", "AUTOMATIC_OPS"):
        m = re.search(r"const " + name + r" := \{(.*?)\}\n", passives, re.S)
        body = m.group(1) if m else ""
        ids |= {int(x) for x in re.findall(r"(\d+):", body)}
    ids |= {int(x) for x in re.findall(r"(?m)^\t(\d+): [\[{]", simple)}
    data = (ROOT / "games/four_souls/logic/fs_data.gd").read_text(encoding="utf-8")
    m = re.search(r"func end_turn_recharge.*?\[(.*?)\]", data, re.S)
    if m:
        ids |= {int(x) for x in re.findall(r"\d+", m.group(1))}
    return ids

AUTOMATED = automated_ids()
table = rows()
support = {}
for card in manifest["cards"]:
    cid = int(card["id"])
    kind = card.get("kind", "")
    lua = card.get("lua", {}) or {}
    t = str(lua.get("type", ""))
    entry = None
    if cid in AUTO:
        entry = {"status": "auto", "hint": AUTO[cid]}
    elif cid in PARTIAL:
        entry = {"status": "partial", "hint": PARTIAL[cid]}
    elif cid in table:
        r = table[cid]
        if "вручную" in r["status"]:
            entry = {"status": "manual", "hint": "Вручную через панель: " + r["expect"] + "."}
        elif "код есть" in r["status"]:
            entry = {"status": "auto", "hint": r["expect"] + " — автоматически."}
        else:
            entry = {"status": "partial" if "код" in r["limit"] else "manual",
                     "hint": "Вручную через панель: " + r["expect"] + ". Движок: " + r["limit"] + "."}
    elif cid in AUTOMATED:
        entry = {"status": "auto", "hint": "Свойство карты учитывается автоматически."}
    elif kind == "loot" and re.fullmatch(r"\dc", t):
        entry = {"status": "auto", "hint": "Монеты — автоматически."}
    elif kind == "loot" and t == "lsoul":
        entry = {"status": "auto", "hint": "Душа — автоматически."}
    elif kind == "monster":
        entry = {"status": "partial", "hint": "Бой — автоматически. Награду и текст монстра выполните через панель эффекта."}
    elif kind in ("bonus", "character"):
        entry = {"status": "partial", "hint": "Учитывается движком; особый текст — через панель эффекта."}
    else:
        entry = {"status": "manual", "hint": "Выполните текст карты через панель эффекта."}
    support[str(cid)] = entry

counts = {}
for e in support.values():
    counts[e["status"]] = counts.get(e["status"], 0) + 1
out = {"_doc": "Статус автоматизации карт Four Souls: auto | partial | manual + подсказка. Генерирует tools/make_fs_card_support.py.",
       "counts": counts, "cards": support}
(ROOT / "games/four_souls/art/card_support.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
print(counts)
