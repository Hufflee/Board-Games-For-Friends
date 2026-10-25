"""Новые ответы «Стиллиона», которые засчитал jev, — сводка для проверки разработчиком.

Игра (у хоста) дописывает каждый засчитанный jev ответ не из списка в user://stillion_new_answers.jsonl
(STJev.NEW_ANSWERS). Скрипт убирает повторы и то, что уже есть в st_questions.gd, и группирует по вопросам.
Верные ответы переносятся в st_questions.gd вручную (строки c:/s:/u:/e:), после — тесты Стиллиона.

Запуск: python -I tools/st_new_answers.py [путь к jsonl]
По умолчанию — %APPDATA%/Godot/app_userdata/Настольные игры с друзьями/stillion_new_answers.jsonl
"""
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUESTIONS = os.path.join(ROOT, "games", "stillion", "logic", "st_questions.gd")
DEFAULT = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Настольные игры с друзьями", "stillion_new_answers.jsonl")
NAMES = {"c": "общеизвестно", "s": "школьник", "u": "умник", "e": "эрудит"}


def normalize(text: str) -> str:
    """Как STJudge.normalize: нижний регистр, ё→е, только буквы/цифры, пробелы схлопнуты."""
    t = text.lower().replace("ё", "е")
    t = re.sub(r"[^0-9a-zа-я]+", " ", t)
    return t.strip()


def known_answers() -> dict:
    src = open(QUESTIONS, encoding="utf-8").read()
    body = src[src.index('const TEXT := """') + 17:]
    body = body[:body.index('"""')]
    known = defaultdict(set)
    q = None
    for line in body.split("\n"):
        line = line.strip()
        if line.startswith("? "):
            q = line[2:]
        elif len(line) > 2 and line[1] == ":" and line[0] in "csue" and q:
            for item in line[2:].split(","):
                for alt in item.strip().rstrip("?").split("|"):
                    if alt.strip():
                        known[q].add(normalize(alt))
    return known


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    path =sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.exists(path):
        print(f"Файла нет: {path} — jev пока не засчитал ни одного нового ответа.")
        return
    known = known_answers()
    by_q = defaultdict(dict)
    for line in open(path, encoding="utf-8"):
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        n = normalize(r.get("answer", ""))
        q = r.get("question", "")
        if not n or n in known.get(q, set()):
            continue
        entry = by_q[q].setdefault(n, {"answer": r.get("answer", ""), "count": 0, "p": [], "rarity": r.get("rarity", ""), "cat": r.get("cat", "")})
        entry["count"] += 1
        entry["p"].append(float(r.get("p", -1)))
    if not by_q:
        print("Новых ответов нет (всё уже в списках).")
        return
    total = 0
    for q, answers in sorted(by_q.items()):
        cat = next(iter(answers.values()))["cat"]
        missing = "" if q in known else "  [вопроса больше нет в списке]"
        print(f"\n[{cat}] {q}{missing}")
        for e in sorted(answers.values(), key=lambda e: -e["count"]):
            p = max(e["p"])
            print(f"  - {e['answer']}  ×{e['count']}  верно≈{p:.2f}  jev: {NAMES.get(e['rarity'], e['rarity'])}")
            total += 1
    print(f"\nВсего новых ответов: {total}")


if __name__ == "__main__":
    main()
