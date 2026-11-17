"""Проверка интерфейса. Запуск из любого каталога: python -I tools/ui_lint.py."""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Ключ — (путь, имя функции, код проверки). Значение — причина исключения.
EXCEPTIONS: dict[tuple[str, str, str], str] = {
    ("games/things_in_rings/ui/tr_lobby.gd", "_player_chip", "обрезка"):
        "В подсказке уже есть полный ник и пояснение выбора ведущего.",
}
RULES = {
    "размер": re.compile(r'(?:["\']font_size["\']\s*,|\bfont_size\s*=)\s*(\d+)\b'),
    "обрезка": re.compile(r"\bclip_text\s*=\s*true\b|\bOVERRUN_TRIM_ELLIPSIS\b"),
    "склонение": re.compile(r'["\'][^"\']*%d\s+(?:карт|очков|монет|фишек|ходов|слов)\b'),
    "карта": re.compile(r"\btooltip_text\b"),
}
CARD_TEXT = re.compile(r"\b(?:card_text|vip_text|gift_name)\b")


def findings(path):
    relative = path.relative_to(ROOT).as_posix()
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    starts = [0]
    starts.extend(i for i, line in enumerate(lines) if i and re.match(r"(?:static )?func ", line))
    for start, end in zip(starts, starts[1:] + [len(lines)]):
        name = re.match(r"(?:static )?func (\w+)", lines[start]) if lines else None
        function = name[1] if name else ""
        body = "\n".join(lines[start:end])
        for i in range(start, end):
            line = lines[i]
            if line.lstrip().startswith("#"):
                continue
            for code, pattern in RULES.items():
                match = pattern.search(line)
                if not match or (relative, function, code) in EXCEPTIONS:
                    continue
                if code == "размер" and int(match[1]) >= 12:
                    continue
                if code == "обрезка" and re.search(r"\.full_on_hover\(|\bautowrap_mode\b", body):
                    continue
                if code == "склонение" and ".plural(" in line:
                    continue
                nearby = "\n".join(lines[max(start, i - 2):min(end, i + 3)])
                if code == "карта" and not CARD_TEXT.search(nearby):
                    continue
                yield f"{relative}:{i + 1}: {code}: {line.strip()}"


def main():
    paths = sorted([*ROOT.glob("games/*/ui/**/*.gd"), *ROOT.glob("hub/**/*.gd")])
    issues = [issue for path in paths for issue in findings(path)]
    for issue in issues:
        print(issue)
    return bool(issues)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
