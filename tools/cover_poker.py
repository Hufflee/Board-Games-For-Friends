"""Обложка «Покера» (своя, рисуется кодом): перед, зад и торец 900×1200 / 168×1200 в hub/covers.
Стиль игры — неоновый Лас-Вегас: фиолетовая ночь, неоновые трубки, овал сукна, гора фишек (games/poker/art/chips).
Запуск: python -I tools/cover_poker.py  (сначала python -I tools/chips_poker.py)
"""
import math

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = "hub/covers/poker_%s.png"
NIGHT = (18, 8, 34)
FELT = (58, 24, 102)
FELT_C = (85, 42, 140)
RAIL = (31, 15, 53)
PINK = (255, 63, 164)
CYAN = (53, 224, 255)
GOLD = (255, 201, 77)
INK = (241, 233, 255)
HEAD = "hub/art/fonts/RussoOne-Regular.ttf"
TEXT = "hub/art/fonts/Exo2-Variable.ttf"


def neon_text(img, xy, text, size, color, anchor="mm"):
	f = ImageFont.truetype(HEAD, size)
	glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
	ImageDraw.Draw(glow).text(xy, text, font=f, fill=color + (255,), anchor=anchor)
	for r, a in ((26, 0.9), (12, 0.9), (4, 1.0)):
		g = glow.filter(ImageFilter.GaussianBlur(r))
		img.alpha_composite(Image.blend(Image.new("RGBA", img.size, (0, 0, 0, 0)), g, a))
	d = ImageDraw.Draw(img)
	d.text(xy, text, font=f, fill=color, anchor=anchor)
	d.text(xy, text, font=f, fill=(255, 255, 255, 150), anchor=anchor, stroke_width=0)


def neon_ellipse(img, box, color, width):
	layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
	ImageDraw.Draw(layer).ellipse(box, outline=color + (255,), width=width)
	for r in (22, 10, 4):
		img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(r)))
	img.alpha_composite(layer)
	ImageDraw.Draw(img).ellipse([box[0] + width // 3, box[1] + width // 3, box[2] - width // 3, box[3] - width // 3], outline=(255, 255, 255, 140), width=max(1, width // 3))


def backdrop(w, h):
	img = Image.new("RGBA", (w, h), NIGHT + (255,))
	glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	d = ImageDraw.Draw(glow)
	d.ellipse([-w * 0.4, -h * 0.2, w * 0.6, h * 0.5], fill=PINK + (60,))
	d.ellipse([w * 0.4, h * 0.0, w * 1.4, h * 0.6], fill=CYAN + (50,))
	d.ellipse([w * 0.0, h * 0.7, w * 1.0, h * 1.3], fill=(155, 92, 255, 70))
	img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(120)))
	# гирлянда лампочек по краю
	d = ImageDraw.Draw(img)
	step = 36
	for x in range(18, w, step):
		for y in (18, h - 18):
			d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=GOLD + (230,))
	for y in range(18 + step, h - 18, step):
		for x in (18, w - 18):
			d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=GOLD + (230,))
	return img


def card(cid, height):
	im = Image.open("games/the_gang/art/cards/%d.webp" % cid).convert("RGBA")
	return im.resize((int(im.width * height / im.height), height), Image.LANCZOS)


def front():
	w, h = 900, 1200
	img = backdrop(w, h)
	d = ImageDraw.Draw(img)
	# стол
	box = [70, 560, 830, 1080]
	d.ellipse([box[0] - 30, box[1] - 30, box[2] + 30, box[3] + 30], fill=RAIL)
	neon_ellipse(img, [box[0] - 30, box[1] - 30, box[2] + 30, box[3] + 30], PINK, 10)
	d = ImageDraw.Draw(img)
	d.ellipse(box, fill=FELT)
	for k in range(6):
		s = 1 - k * 0.12
		cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
		rx, ry = (box[2] - box[0]) / 2 * s, (box[3] - box[1]) / 2 * s
		d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=FELT_C + (40,))
	neon_ellipse(img, [box[0] + 18, box[1] + 18, box[2] - 18, box[3] - 18], CYAN, 4)
	# пара тузов веером и гора фишек
	for i, (cid, ang, dx) in enumerate(((12, 12, -70), (51, -10, 40))):
		c = card(cid, 330).rotate(ang, expand=True, resample=Image.BICUBIC)
		img.alpha_composite(c, (int(w / 2 - c.width / 2 + dx - 170), 600))
	pile = Image.open("games/poker/art/chips/pile_5.png").convert("RGBA")
	pile = pile.resize((pile.width * 2, pile.height * 2), Image.LANCZOS)
	img.alpha_composite(pile, (int(w / 2 - 30), 690))
	neon_text(img, (w / 2, 250), "ПОКЕР", 190, PINK)
	neon_text(img, (w / 2, 420), "NEON HOLD'EM", 64, CYAN)
	f = ImageFont.truetype(TEXT, 40)
	ImageDraw.Draw(img).text((w / 2, 505), "2–8 игроков · классика и спорт", font=f, fill=INK, anchor="mm")
	img.convert("RGB").save(OUT % "front")


def back():
	w, h = 900, 1200
	img = backdrop(w, h)
	neon_text(img, (w / 2, 150), "ТЕХАССКИЙ ХОЛДЕМ", 70, CYAN)
	d = ImageDraw.Draw(img)
	f = ImageFont.truetype(TEXT, 40)
	lines = [
		"Две карты в руке, пять на столе.",
		"Блефуйте, повышайте, идите ва-банк.",
		"",
		"«Классика» — раздачи без конца,",
		"проиграли — садитесь заново со 100 BB.",
		"",
		"«Спортивный» — сессии по 14 раздач,",
		"очки за места, до 2N+1 очков.",
	]
	for i, line in enumerate(lines):
		d.text((w / 2, 290 + i * 58), line, font=f, fill=INK, anchor="mm")
	for i, cid in enumerate((8, 9, 10, 11, 12)):
		c = card(cid, 220)
		img.alpha_composite(c, (int(110 + i * 140), 820))
	img.convert("RGB").save(OUT % "back")


def spine():
	w, h = 168, 1200
	img = backdrop(w, h)
	txt = Image.new("RGBA", (h, w), (0, 0, 0, 0))
	neon_text(txt, (h / 2, w / 2), "ПОКЕР", 110, PINK)
	img.alpha_composite(txt.rotate(90, expand=True))
	img.convert("RGB").save(OUT % "spine")


if __name__ == "__main__":
	front()
	back()
	spine()
	print("обложка готова")
