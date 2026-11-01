"""Собственные минимальные JSON-игры для проверки ядра редактора; без чужих текстов и ассетов."""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "games/custom/examples"
OUT.mkdir(parents=True, exist_ok=True)


def expr(op, **fields):
    return {"op": op, **fields}


ACTOR = expr("actor")
CARD = expr("card")
HAND = expr("zone", id="hand", player=ACTOR)


def base(title):
    return {
        "format": 1, "id": title.lower().replace(" ", "_"), "game_version": 1,
        "meta": {"title": title, "players": [2, 8], "time": "5 минут", "description": "Пример редактора"},
        "elements": {"decks": [{"id": "draw", "size": 3, "rows": [{"rank": n, "copies": 1} for n in range(1, 31)]}]},
        "layout": {"screens": [{"id": "main", "items": [
            {"kind": "zone", "id": "draw", "title": "Колода", "owner": "shared", "view": "pile"},
            {"kind": "zone", "id": "hand", "title": "Ваша рука", "owner": "player", "view": "fan"},
            {"kind": "zone", "id": "table", "title": "На столе", "owner": "shared", "view": "discard"},
        ]}]},
        "rules": {"phases": ["setup", "turn"], "turns": "round", "vars": [], "chains": []},
    }


def chain(kind, blocks, **event):
    return {"event": {"type": kind, **event}, "blocks": blocks}


def save(name, game):
    labels = {"score": "Очки", "previous": "Предыдущая", "draws": "Открыто", "bid": "Ставка", "bidder": "Ставил"}
    for variable in game["rules"]["vars"]:
        variable["title"] = labels.get(variable["id"], variable["id"])
    game["meta"]["phase_titles"] = {"setup": "Подготовка", "turn": "Ход игрока", "game_over": "Итоги"}
    game["meta"]["action_titles"] = {"draw": "Взять карту", "raise": "Поднять ставку", "challenge": "Проверить", "higher": "Больше", "lower": "Меньше"}
    (OUT / (name + ".json")).write_text(json.dumps(game, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


game = base("Карточная гонка")
game["rules"]["vars"] = [{"id": "score", "scope": "player", "type": "number", "init": 0}]
game["rules"]["chains"] = [
    chain("start", [expr("shuffle", zone="draw"), expr("deal", **{"from": "draw", "to": HAND, "count": 3}), expr("phase", phase="turn")]),
    chain("card", [expr("move", card=CARD, to="table"), expr("open", card=CARD),
        expr("change", var="score", value=expr("property", card=CARD, field="rank")),
        expr("if", condition=expr("eq", a=expr("count", zone=HAND), b=0), then=[expr("win", player=ACTOR)], **{"else": [expr("next")]})],
        id="play", phase="turn", by="current", zone=HAND),
]
save("card_race", game)

game = base("Больше или меньше")
game["rules"]["vars"] = [
    {"id": "previous", "scope": "shared", "type": "number", "init": 0},
    {"id": "draws", "scope": "shared", "type": "number", "init": 0},
    {"id": "score", "scope": "player", "type": "number", "init": 0},
]
game["rules"]["chains"] = [chain("start", [expr("shuffle", zone="draw"), expr("draw", **{"from": "draw", "to": "table", "count": 1}), expr("open", card=CARD), expr("set", var="previous", value=expr("property", card=CARD, field="rank")), expr("phase", phase="turn")])]
for direction, comparison in [("higher", "gt"), ("lower", "lt")]:
    game["rules"]["chains"].append(chain("button", [expr("draw", **{"from": "draw", "to": "table", "count": 1}), expr("open", card=CARD),
        expr("if", condition=expr(comparison, a=expr("property", card=CARD, field="rank"), b=expr("var", id="previous")), then=[expr("change", var="score", value=1)]),
        expr("set", var="previous", value=expr("property", card=CARD, field="rank")), expr("change", var="draws", value=1),
        expr("if", condition=expr("ge", a=expr("var", id="draws"), b=10), then=[expr("finish", var="score")], **{"else": [expr("next")]})],
        id=direction, phase="turn", by="current"))
save("higher_lower", game)

game = base("Проверка ставки")
game["elements"]["decks"] = []
game["layout"]["screens"][0]["items"] = [{"kind": "dice_tray", "id": "dice", "title": "Кубики игроков"}]
game["rules"]["vars"] = [
    {"id": "bid", "scope": "shared", "type": "number", "init": 0},
    {"id": "bidder", "scope": "shared", "type": "number", "init": 0},
]
raise_chain = chain("button", [expr("set", var="bidder", value=ACTOR), expr("change", var="bid", value=1), expr("next")], id="raise", phase="turn", by="current")
raise_chain["guard"] = expr("lt", a=expr("var", id="bid"), b=12)
challenge = chain("button", [expr("if", condition=expr("lt", a=expr("dice_count", face=3), b=expr("var", id="bid")),
    then=[expr("win", player=ACTOR)], **{"else": [expr("win", player=expr("var", id="bidder"))]})], id="challenge", phase="turn", by="current")
challenge["guard"] = expr("gt", a=expr("var", id="bid"), b=0)
game["rules"]["chains"] = [chain("start", [expr("each_player", body=[expr("roll", count=2, visible="owner")]), expr("phase", phase="turn")]), raise_chain, challenge]
save("dice_bid", game)
