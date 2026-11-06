"""Things in Rings: новые карты условий (72 шт.) — картинки и строки каталога.

Рамка берётся с оригинальной карты своей категории (текст стирается),
надпись печатается Balsamiq Sans с обводкой того же цвета (жирность).
Запуск из корня: python -I tools/tr_make_rule_cards.py   (повторный запуск безопасен)
"""
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
CARDS = ROOT / "games/things_in_rings/art/cards"
CATALOG = ROOT / "games/things_in_rings/logic/tr_catalog.json"
FONT = ROOT / "editor/fonts/base/balsamiq/font.ttf"
# Оригинальная карта-источник рамки и первый свободный id по категории.
SOURCE = {"Attribute": (300, 324), "Word": (204, 224), "Context": (421, 424)}

RULES = {
	"Attribute": [
		("CONTAINS METAL", "Содержит металл"),
		("CONTAINS GLASS", "Содержит стекло"),
		("CONTAINS FABRIC OR CLOTH", "Содержит ткань"),
		("SOFT TO THE TOUCH", "Мягкое на ощупь"),
		("USES ELECTRICITY", "Работает от электричества"),
		("HAS MOVING PARTS", "Есть движущиеся части"),
		("HAS A HANDLE", "Есть ручка"),
		("HAS LEGS OR WHEELS", "Есть ноги или колёса"),
		("HAS EYES", "Есть глаза"),
		("EDIBLE", "Съедобное"),
		("HAS A NOTICEABLE SMELL", "Имеет заметный запах"),
		("USUALLY WARM OR HOT", "Обычно тёплое или горячее"),
		("USUALLY COLD", "Обычно холодное"),
		("OFTEN RED, ORANGE OR YELLOW", "Часто красное, оранжевое или жёлтое"),
		("OFTEN GREEN OR BLUE", "Часто зелёное или синее"),
		("FITS IN A POCKET", "Помещается в карман"),
		("MUCH LONGER THAN IT IS WIDE", "Намного длиннее, чем шире"),
		("HAS A LID, DOOR OR COVER", "Есть крышка, дверца или чехол"),
		("CAN HOLD WATER", "Может удерживать воду"),
		("CAN BE FOLDED OR ROLLED UP", "Можно сложить или свернуть"),
		("USUALLY COMES IN PAIRS", "Обычно бывает парой"),
		("BENDS WITHOUT BREAKING", "Гнётся и не ломается"),
		("GLOWS OR GIVES OFF LIGHT", "Светится или даёт свет"),
		("SQUARE OR BOXY", "Квадратное или в форме коробки"),
	],
	"Word": [
		("HAS AN “E”", "В названии есть буква E"),
		("HAS AN “A”", "В названии есть буква A"),
		("HAS AN “I”", "В названии есть буква I"),
		("HAS AN “S”", "В названии есть буква S"),
		("HAS A “T”", "В названии есть буква T"),
		("HAS AN “L”", "В названии есть буква L"),
		("HAS AN “N”", "В названии есть буква N"),
		("HAS A “P” OR “B”", "В названии есть буква P или B"),
		("HAS A “C” OR “K”", "В названии есть буква C или K"),
		("HAS A “J”, “K”, “Q”, “V”, “W”, “X” OR “Z”", "В названии есть J, K, Q, V, W, X или Z"),
		("ENDS WITH A VOWEL (NOT INCLUDING “Y”)", "Название заканчивается гласной, без учёта Y"),
		("7 OR MORE LETTERS LONG", "Название длиной от 7 букв"),
		("HAS AN EVEN NUMBER OF LETTERS", "В названии чётное число букв"),
		("HAS EXACTLY 3 VOWELS", "В названии ровно 3 гласные"),
		("HAS 3 OR MORE DIFFERENT VOWELS", "В названии 3 или больше разные гласные"),
		("HAS 3 OR MORE SYLLABLES", "В названии 3 слога или больше"),
		("STARTS WITH 2 CONSONANTS (E.G. STAR, CLOCK)", "Название начинается с двух согласных (например STAR, CLOCK)"),
		("FIRST AND LAST LETTERS ARE BOTH “A”–“M”", "Первая и последняя буквы — обе от A до M"),
		("LAST LETTER COMES LATER IN THE ALPHABET THAN THE FIRST", "Последняя буква стоит в алфавите дальше первой"),
		("NO LETTERS AFTER “S” IN THE ALPHABET", "В названии нет букв дальше S по алфавиту"),
		("HAS 2 ALPHABET NEIGHBORS SIDE BY SIDE (E.G. “ST”, “ED”)", "В названии рядом стоят две соседние по алфавиту буквы (например ST, ED)"),
		("VOWELS AND CONSONANTS ALTERNATE (E.G. BANANA)", "Гласные и согласные чередуются (например BANANA)"),
		("AT LEAST TWICE AS MANY CONSONANTS AS VOWELS", "Согласных минимум вдвое больше, чем гласных"),
		("ENDS WITH “ER”, “LE”, “ON”, “EL”, “ET”, “EN” OR “AN”", "Оканчивается на ER, LE, ON, EL, ET, EN или AN"),
	],
	"Context": [
		("FOUND IN A KITCHEN", "Встречается на кухне"),
		("FOUND IN A BATHROOM", "Встречается в ванной"),
		("FOUND AT THE BEACH OR NEAR WATER", "Встречается на пляже или у воды"),
		("FOUND IN A CITY CENTER", "Встречается в центре города"),
		("FOUND IN A HOSPITAL", "Встречается в больнице"),
		("YOU’D SEE IT IN A MUSEUM", "Это можно увидеть в музее"),
		("CHILDREN PLAY WITH IT", "С этим играют дети"),
		("USED IN SPORTS OR GAMES", "Используется в спорте или играх"),
		("A GOOD GIFT", "Хороший подарок"),
		("ASSOCIATED WITH A HOLIDAY", "Связано с каким-то праздником"),
		("INVENTED IN THE LAST 100 YEARS", "Изобретено за последние 100 лет"),
		("ASSOCIATED WITH WINTER", "Связано с зимой"),
		("ASSOCIATED WITH NIGHT", "Связано с ночью"),
		("MANY PEOPLE ARE AFRAID OF IT", "Многие этого боятся"),
		("MOST PEOPLE HAVE NEVER SEEN ONE IN REAL LIFE", "Большинство никогда не видели это вживую"),
		("PEOPLE COLLECT IT", "Это коллекционируют"),
		("YOU CAN RENT IT", "Это можно взять напрокат"),
		("NEEDS A LICENSE OR PERMISSION", "Нужны права или разрешение"),
		("NEEDS REGULAR CARE", "Требует регулярного ухода"),
		("USUALLY SHARED BY MANY PEOPLE", "Обычно этим пользуются многие сразу"),
		("USUALLY BELONGS TO ONE PERSON", "Обычно принадлежит одному человеку"),
		("USUALLY COSTS LESS THAN $5", "Обычно стоит меньше 5 долларов"),
		("YOU’D PACK IT FOR A VACATION", "Это берут с собой в отпуск"),
		("PEOPLE OFTEN TAKE PHOTOS OF IT", "Это часто фотографируют"),
	],
}

# Белое поле внутри зубчатой рамки (для карты 508×772): стираем здесь старый текст.
FIELD = (62, 90, 446, 682)
TEXT_W = 340
INK = (24, 22, 26)


def blank(kind: str) -> Image.Image:
	src = Image.open(CARDS / f"{SOURCE[kind][0]}.webp").convert("RGB")
	field = src.crop(FIELD)
	light = [p for p in field.getdata() if sum(p) > 600]
	paper = tuple(sorted(c)[len(c) // 2] for c in zip(*light))
	# Тёмные пиксели текста → бумага; затем мягко сглаживаем следы.
	clean = Image.new("RGB", field.size, paper)
	ink = field.convert("L").point(lambda v: 255 if v < 232 else 0).filter(ImageFilter.MaxFilter(9))
	clean.paste(field, mask=ink.point(lambda v: 255 - v))
	clean = clean.filter(ImageFilter.GaussianBlur(6))
	src.paste(clean, FIELD[:2])
	return src


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> list:
	lines, line = [], ""
	for word in text.split():
		probe = (line + " " + word).strip()
		if draw.textlength(probe, font=font) <= TEXT_W or not line:
			line = probe
		else:
			lines.append(line)
			line = word
	if line:
		lines.append(line)
	return lines


def render(kind: str, text: str) -> Image.Image:
	card = blank(kind)
	draw = ImageDraw.Draw(card)
	main, _, example = text.partition(" (")
	example = "(" + example if example else ""
	size = 46
	while True:
		big = ImageFont.truetype(str(FONT), size)
		small = ImageFont.truetype(str(FONT), int(size * 0.72))
		rows = [(l, big, size * 1.3) for l in wrap(draw, main, big)]
		if example:
			rows.append(("", small, size * 0.35))
			rows += [(l, small, size * 0.82) for l in wrap(draw, example, small)]
		height = sum(r[2] for r in rows)
		if height <= FIELD[3] - FIELD[1] - 80 or size <= 30:
			break
		size -= 2
	y = (FIELD[1] + FIELD[3]) / 2 - height / 2
	for line, font, step in rows:
		if line:
			draw.text((card.width / 2, y + step / 2), line, font=font, fill=INK, anchor="mm",
				stroke_width=2 if font is big else 1, stroke_fill=INK)
		y += step
	return card


def main() -> None:
	rows = json.loads(CATALOG.read_text(encoding="utf-8"))
	by_id = {int(r["id"]): r for r in rows}
	for kind, rules in RULES.items():
		first = SOURCE[kind][1]
		for n, (en, ru) in enumerate(rules):
			card_id = first + n
			image = render(kind, en)
			path = CARDS / f"{card_id}.webp"
			image.save(path, "WEBP", quality=92, method=6)
			row = {"id": card_id, "kind": kind, "file": path.name, "size": list(image.size),
				"sheet": "custom", "index": n,
				"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "en": en, "ru": ru}
			if card_id in by_id and by_id[card_id].get("sheet") != "custom":
				raise SystemExit(f"id {card_id} уже занят оригинальной картой")
			by_id[card_id] = row
	out = [by_id[k] for k in sorted(by_id, key=lambda i: [r["id"] for r in rows].index(i) if i in [r["id"] for r in rows] else 10**6 + i)]
	CATALOG.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
	print("карт условий:", sum(1 for r in out if r["kind"] != "Thing"), "всего:", len(out))


if __name__ == "__main__":
	main()
