"""Рождественские стикеры хаба (открываются 13 ноября — см. hub/stickers.gd, SEASONS).

Те же 256×256 PNG с белой вырубкой, что и в tools/hub_stickers.py: часть — эмодзи Segoe UI Emoji,
карамельная трость и шар-игрушка — нарисованы кодом.
Запуск из корня проекта:  python -I tools/hub_stickers_xmas.py [папка]   (по умолчанию hub/art/stickers)
После — импорт ресурсов Godot: godot --headless --path . --import
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hub_stickers import canvas, die_cut, emoji  # noqa: E402

from PIL import Image, ImageDraw  # noqa: E402

EMOJI = {
	"xmas_tree": "\U0001F384",
	"xmas_santa": "\U0001F385",
	"xmas_gift": "\U0001F381",
	"xmas_snowman": "⛄",
	"xmas_bell": "\U0001F514",
	"xmas_deer": "\U0001F98C",
	"xmas_sock": "\U0001F9E6",
}


def candy_cane() -> Image.Image:
	"""Карамельная трость: белая с красными косыми полосами."""
	mask = Image.new("L", (256, 256), 0)
	d = ImageDraw.Draw(mask)
	d.arc((70, 30, 170, 130), 180, 360, fill=255, width=34)
	d.line((87, 80, 87, 226), fill=255, width=34)
	d.ellipse((70, 209, 104, 243), fill=255)
	d.ellipse((153, 63, 187, 97), fill=255)
	stripes = Image.new("RGBA", (256, 256), (250, 246, 250, 255))
	sd = ImageDraw.Draw(stripes)
	for k in range(-10, 20):
		x = k * 26
		sd.polygon([(x, 0), (x + 13, 0), (x + 13 - 256, 256), (x - 256, 256)], fill=(218, 30, 52, 255))
	art = canvas()
	art.paste(stripes, (0, 0), mask)
	shine = Image.new("L", (256, 256), 0)
	ImageDraw.Draw(shine).line((80, 90, 80, 210), fill=90, width=6)
	white = Image.new("RGBA", (256, 256), (255, 255, 255, 255))
	art.paste(white, (0, 0), Image.composite(shine, Image.new("L", (256, 256), 0), mask))
	return art.rotate(-14, resample=Image.BICUBIC)


def snowflake() -> Image.Image:
	"""Снежинка: шесть лучей с веточками, голубая с белой серединкой."""
	import math
	art = canvas()
	d = ImageDraw.Draw(art)
	c = 128
	blue = (70, 170, 245, 255)
	for i in range(6):
		a = math.radians(i * 60 - 90)
		dx, dy = math.cos(a), math.sin(a)
		d.line((c, c, c + dx * 100, c + dy * 100), fill=blue, width=18)
		for at, arm in ((48, 34), (76, 24)):
			px, py = c + dx * at, c + dy * at
			for side in (-1, 1):
				b = a + side * math.radians(45)
				d.line((px, py, px + math.cos(b) * arm, py + math.sin(b) * arm), fill=blue, width=13)
		d.ellipse((c + dx * 100 - 9, c + dy * 100 - 9, c + dx * 100 + 9, c + dy * 100 + 9), fill=blue)
	d.ellipse((c - 22, c - 22, c + 22, c + 22), fill=blue)
	d.ellipse((c - 11, c - 11, c + 11, c + 11), fill=(235, 248, 255, 255))
	return art


def bauble() -> Image.Image:
	"""Шар-игрушка: красный с золотым колпачком, бликом и белым узором."""
	art = canvas()
	d = ImageDraw.Draw(art)
	d.rectangle((112, 36, 144, 62), fill=(230, 180, 60, 255), outline=(140, 96, 20, 255), width=4)
	d.arc((114, 14, 142, 42), 180, 360, fill=(140, 96, 20, 255), width=5)
	d.ellipse((44, 56, 212, 224), fill=(214, 28, 52, 255), outline=(120, 10, 30, 255), width=6)
	for y in (118, 162):
		d.line((52, y, 204, y), fill=(250, 240, 245, 255), width=8)
	for x in range(70, 200, 22):
		d.ellipse((x - 5, 135, x + 5, 145), fill=(250, 240, 245, 255))
	d.ellipse((78, 76, 116, 104), fill=(255, 150, 160, 160))
	return art


def main() -> None:
	out = sys.argv[1] if len(sys.argv) > 1 else os.path.join("hub", "art", "stickers")
	os.makedirs(out, exist_ok=True)
	for name, char in EMOJI.items():
		die_cut(emoji(char)).save(os.path.join(out, name + ".png"))
	die_cut(candy_cane()).save(os.path.join(out, "xmas_candy.png"))
	die_cut(snowflake()).save(os.path.join(out, "xmas_snowflake.png"))
	die_cut(bauble()).save(os.path.join(out, "xmas_bauble.png"))
	print("готово:", out)


if __name__ == "__main__":
	main()
