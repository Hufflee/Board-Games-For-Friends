"""Стикеры хаба: 10 тестовых наклеек для коробок и доски друзей (256×256 PNG с белой вырубкой и тенью).

5 — из обычных эмодзи (Segoe UI Emoji, шрифт Windows), 5 — нарисованы здесь кодом.
Запуск из корня проекта:  python -I tools/hub_stickers.py [папка]   (по умолчанию hub/art/stickers)
После — импорт ресурсов Godot: godot --headless --path . --import
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SIZE = 256
EMOJI_FONT = r"C:\Windows\Fonts\seguiemj.ttf"
TEXT_FONT = r"C:\Windows\Fonts\segoeuib.ttf"

# id → эмодзи (порядок — как в каталоге hub/stickers.gd)
EMOJI = {
	"fire": "\U0001F525",
	"mind_blown": "\U0001F92F",
	"joy": "\U0001F602",
	"skull": "\U0001F480",
	"thumbs_up": "\U0001F44D",
}


def die_cut(art: Image.Image, border: int = 10) -> Image.Image:
	"""Белая вырубка вокруг рисунка + мягкая тень снизу: выглядит как настоящая наклейка."""
	alpha = art.split()[3].point(lambda a: 255 if a > 24 else 0)
	outline = alpha.filter(ImageFilter.MaxFilter(border * 2 + 1)).filter(ImageFilter.GaussianBlur(1.2))
	outline = outline.point(lambda a: 255 if a > 100 else int(a * 2.4))
	shadow = outline.filter(ImageFilter.GaussianBlur(5)).point(lambda a: int(a * 0.45))
	out = Image.new("RGBA", art.size, (0, 0, 0, 0))
	dark = Image.new("RGBA", art.size, (20, 10, 40, 255))
	dark.putalpha(shadow)
	out.alpha_composite(dark, (0, 5))
	white = Image.new("RGBA", art.size, (250, 248, 255, 255))
	white.putalpha(outline)
	out.alpha_composite(white)
	out.alpha_composite(art)
	return out


def canvas() -> Image.Image:
	return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def emoji(char: str) -> Image.Image:
	font = ImageFont.truetype(EMOJI_FONT, 109)  # цветные глифы Segoe рисуются в своём размере
	glyph = Image.new("RGBA", (220, 220), (0, 0, 0, 0))
	ImageDraw.Draw(glyph).text((110, 110), char, font=font, embedded_color=True, anchor="mm")
	box = glyph.getbbox()
	glyph = glyph.crop(box)
	scale = 196 / max(glyph.size)
	glyph = glyph.resize((max(1, round(glyph.width * scale)), max(1, round(glyph.height * scale))), Image.LANCZOS)
	art = canvas()
	art.alpha_composite(glyph, ((SIZE - glyph.width) // 2, (SIZE - glyph.height) // 2))
	return art


def neon_die() -> Image.Image:
	"""Кубик-шестёрка: фиолетовый, с розовыми точками и бликом."""
	art = canvas()
	d = ImageDraw.Draw(art)
	d.rounded_rectangle((40, 40, 216, 216), 34, fill=(122, 74, 214, 255), outline=(60, 30, 120, 255), width=6)
	d.rounded_rectangle((52, 50, 204, 120), 26, fill=(160, 120, 240, 120))
	for x in (88, 168):
		for y in (84, 128, 172):
			d.ellipse((x - 15, y - 15, x + 15, y + 15), fill=(255, 92, 182, 255), outline=(255, 230, 245, 255), width=3)
	return art.rotate(-12, resample=Image.BICUBIC)


def crown() -> Image.Image:
	"""Золотая корона победителя."""
	art = canvas()
	d = ImageDraw.Draw(art)
	points = [(36, 196), (36, 92), (82, 140), (128, 64), (174, 140), (220, 92), (220, 196)]
	d.polygon(points, fill=(255, 196, 54, 255), outline=(150, 92, 10, 255), width=6)
	d.rectangle((36, 176, 220, 208), fill=(236, 160, 30, 255), outline=(150, 92, 10, 255), width=6)
	for x, y, c in ((82, 192, (64, 210, 255)), (128, 192, (255, 70, 120)), (174, 192, (90, 230, 120))):
		d.ellipse((x - 11, y - 11, x + 11, y + 11), fill=c + (255,), outline=(120, 70, 10, 255), width=3)
	for x, y in ((36, 92), (128, 64), (220, 92)):
		d.ellipse((x - 12, y - 12, x + 12, y + 12), fill=(255, 236, 150, 255), outline=(150, 92, 10, 255), width=4)
	return art


def gg_bubble() -> Image.Image:
	"""Облачко «GG!» — «хорошая игра»."""
	art = canvas()
	d = ImageDraw.Draw(art)
	d.rounded_rectangle((28, 46, 228, 176), 44, fill=(53, 230, 209, 255), outline=(14, 90, 98, 255), width=7)
	d.polygon([(70, 168), (58, 222), (116, 172)], fill=(53, 230, 209, 255), outline=(14, 90, 98, 255))
	d.line([(70, 172), (58, 222), (112, 174)], fill=(14, 90, 98, 255), width=7, joint="curve")
	d.rectangle((72, 160, 112, 172), fill=(53, 230, 209, 255))
	font = ImageFont.truetype(TEXT_FONT, 92)
	d.text((128, 110), "GG!", font=font, fill=(255, 255, 255, 255), anchor="mm", stroke_width=6, stroke_fill=(14, 90, 98, 255))
	return art


def neon_star() -> Image.Image:
	"""Неоновая звезда с искрами."""
	art = canvas()
	glow = canvas()
	gd = ImageDraw.Draw(glow)
	cx, cy = 128, 132
	pts = []
	for i in range(10):
		r = 96 if i % 2 == 0 else 42
		a = -math.pi / 2 + i * math.pi / 5
		pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
	gd.polygon(pts, fill=(255, 62, 165, 255))
	art.alpha_composite(glow.filter(ImageFilter.GaussianBlur(9)))
	d = ImageDraw.Draw(art)
	d.polygon(pts, fill=(255, 120, 200, 255), outline=(150, 20, 90, 255), width=6)
	inner = [(cx + (p[0] - cx) * 0.55, cy + (p[1] - cy) * 0.55 - 4) for p in pts]
	d.polygon(inner, fill=(255, 220, 240, 200))
	for x, y, s in ((210, 46, 16), (40, 60, 11), (218, 200, 10)):
		d.polygon([(x, y - s), (x + s / 3, y - s / 3), (x + s, y), (x + s / 3, y + s / 3), (x, y + s), (x - s / 3, y + s / 3), (x - s, y), (x - s / 3, y - s / 3)], fill=(255, 245, 160, 255))
	return art


def pixel_heart() -> Image.Image:
	"""Пиксельное сердечко из ретро-игр."""
	pattern = [
		"..XX...XX..",
		".XWWX.XRRX.",
		"XWWRRXRRRRX",
		"XWRRRRRRRRX",
		"XRRRRRRRRRX",
		".XRRRRRRRX.",
		"..XRRRRRX..",
		"...XRRRX...",
		"....XRX....",
		".....X.....",
	]
	art = canvas()
	d = ImageDraw.Draw(art)
	cell = 19
	ox = (SIZE - cell * len(pattern[0])) // 2
	oy = (SIZE - cell * len(pattern)) // 2 + 6
	colors = {"X": (60, 10, 40, 255), "R": (232, 40, 90, 255), "W": (255, 190, 210, 255)}
	for y, row in enumerate(pattern):
		for x, ch in enumerate(row):
			if ch in colors:
				d.rectangle((ox + x * cell, oy + y * cell, ox + (x + 1) * cell - 1, oy + (y + 1) * cell - 1), fill=colors[ch])
	return art


def six_seven() -> Image.Image:
	"""Мем «6 7»: две крупные цифры разного цвета, чуть враскачку."""
	art = canvas()
	font = ImageFont.truetype(TEXT_FONT, 150)
	for ch, x, y, angle, fill, stroke in (("6", 82, 132, 10, (255, 196, 54), (120, 60, 10)), ("7", 172, 120, -10, (53, 230, 209), (14, 90, 98))):
		layer = canvas()
		ImageDraw.Draw(layer).text((x, y), ch, font=font, fill=fill + (255,), anchor="mm", stroke_width=9, stroke_fill=stroke + (255,))
		art.alpha_composite(layer.rotate(angle, center=(x, y), resample=Image.BICUBIC))
	return art


CUSTOM = {
	"neon_die": neon_die,
	"crown": crown,
	"gg": gg_bubble,
	"neon_star": neon_star,
	"pixel_heart": pixel_heart,
	"six_seven": six_seven,
}


def main() -> None:
	sys.stdout.reconfigure(encoding="utf-8")
	out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join("hub", "art", "stickers")
	os.makedirs(out_dir, exist_ok=True)
	for name, char in EMOJI.items():
		die_cut(emoji(char)).save(os.path.join(out_dir, name + ".png"))
		print("эмодзи", name)
	for name, draw in CUSTOM.items():
		die_cut(draw()).save(os.path.join(out_dir, name + ".png"))
		print("своя", name)
	# Лист для просмотра: все 10 на тёмном фоне.
	sheet = Image.new("RGBA", (SIZE * 6, SIZE * 2), (38, 24, 70, 255))
	for i, name in enumerate(list(EMOJI) + list(CUSTOM)):
		sheet.alpha_composite(Image.open(os.path.join(out_dir, name + ".png")), ((i % 6) * SIZE, (i // 6) * SIZE))
	os.makedirs(os.path.join("build", "shots"), exist_ok=True)
	sheet.save(os.path.join("build", "shots", "hub_stickers_sheet.png"))


if __name__ == "__main__":
	main()
