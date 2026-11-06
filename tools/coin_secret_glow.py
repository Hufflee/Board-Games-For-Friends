"""Свечение для всех секретных монет антистресса (пакет 06.11.2026).
Берёт секретные текстуры из hub/fidget.gd (ключи *_secret и doubloon_gold), находит самые яркие места
каждой монеты (верхние ~4 % по местной яркости: символы, искры, огни, а не светлые поля) и даёт вокруг
них мягкий ореол (screen) их же насыщенным цветом.
Прозрачность не меняется: ореол только внутри монеты (за ободком fidget всё равно обрезает).
Machi Koro пропускается — свечение у неё нарисовано в tools/coin_machi_koro.py.
Запуск из корня: python -I tools/coin_secret_glow.py [папка] [--apply]
  без --apply → в папку (по умолчанию hub/art/coins/variants/glow_2026-11-06/), оригиналы не трогает; + _compare.png (до/после).
  --apply → заменяет игровые монеты; исходники без свечения хранятся в backups/coin_glow_1106/ и берутся оттуда.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
FIDGET = ROOT / "hub/fidget.gd"
SKIP = {"machi_koro_secret_coin.png"}
BACKUP = ROOT / "backups/coin_glow_1106"  # монеты без свечения
SHARE = 0.04  # доля самых «выделяющихся» пикселей монеты, которые светятся
STRENGTH = 0.7  # сила ореола


def secret_files() -> list:
	text = FIDGET.read_text(encoding="utf-8")
	consts = {"COINS": "res://hub/art/coins/", "COIN_VARIANTS": "res://hub/art/coins/variants/codex_2026-10-23/"}
	files = []
	for key, body in re.findall(r'^\t"(\w+)": \[(.+?)\],', text, re.M):
		if not (key.endswith("_secret") or key == "doubloon_gold"):
			continue
		for part in body.split(","):
			part = part.strip()
			m = re.match(r'(?:(\w+) \+ )?"([^"]+)"', part)
			if not m:
				continue
			path = (consts.get(m.group(1), "") if m.group(1) else "") + m.group(2)
			path = ROOT / path.replace("res://", "")
			if path.name not in SKIP and path not in files:
				files.append(path)
	return files


def glow(img: Image.Image) -> Image.Image:
	rgba = img.convert("RGBA")
	alpha = rgba.split()[3]
	rgb = rgba.convert("RGB")
	side = min(img.size)
	_, s, v = rgb.convert("HSV").split()
	# Светится то, что заметно ярче своего окружения: символы, искры, огни — а не большие светлые поля.
	local = ImageChops.subtract(v, v.filter(ImageFilter.GaussianBlur(side * 0.035)))
	score = ImageChops.multiply(local.point(lambda x: min(255, x * 4)), v)
	score = ImageChops.multiply(score, s.point(lambda x: 120 + x // 2 if x > 0 else 120))
	inner = alpha.point(lambda a: 255 if a > 200 else 0).filter(ImageFilter.MinFilter(max(3, int(side * 0.02) | 1)))
	score = ImageChops.multiply(score, inner)
	hist = score.histogram()
	total = sum(hist[1:])
	acc, cut = 0, 255
	for level in range(255, 0, -1):
		acc += hist[level]
		if acc >= total * SHARE:
			cut = level
			break
	cut = max(cut, 40)
	mask = score.point(lambda x: 255 if x >= cut else 0).filter(ImageFilter.MaxFilter(3))
	near = mask.filter(ImageFilter.GaussianBlur(side * 0.01)).point(lambda x: min(255, int(x * 2.4)))
	wide = mask.filter(ImageFilter.GaussianBlur(side * 0.028)).point(lambda x: min(255, int(x * 1.6)))
	halo = ImageChops.lighter(near, wide)
	# Цвет ореола — насыщенный средний цвет светящихся мест.
	small = rgb.resize((256, 256))
	pix = [c for c, m in zip(small.getdata(), mask.resize((256, 256)).getdata()) if m > 128]
	if pix:
		avg = [sum(c[i] for c in pix) / len(pix) for i in range(3)]
		top = max(avg) or 1
		tint = tuple(min(255, int(x / top * 255)) for x in avg)
	else:
		tint = (255, 214, 120)
	light = Image.composite(Image.new("RGB", rgb.size, tint), Image.new("RGB", rgb.size, (0, 0, 0)),
		halo.point(lambda x: int(x * STRENGTH)))
	out = ImageChops.screen(rgb, light).convert("RGBA")
	out.putalpha(alpha)
	return out


def compare(pairs: list, out: Path) -> None:
	cell = 220
	rows = []
	for bg in ((233, 225, 211), (31, 28, 37)):
		sheet = Image.new("RGBA", (cell * 4, cell * ((len(pairs) + 1) // 2)), bg + (255,))
		for i, (before, after) in enumerate(pairs):
			x, y = (i % 2) * cell * 2, (i // 2) * cell
			for k, im in enumerate((before, after)):
				th = im.copy()
				th.thumbnail((cell - 10, cell - 10))
				sheet.alpha_composite(th, (x + k * cell + (cell - th.width) // 2, y + (cell - th.height) // 2))
		rows.append(sheet)
	full = Image.new("RGB", (rows[0].width * 2 + 20, rows[0].height), (128, 128, 128))
	full.paste(rows[0].convert("RGB"), (0, 0))
	full.paste(rows[1].convert("RGB"), (rows[0].width + 20, 0))
	full.save(out)
	print(out)


def main() -> None:
	apply = "--apply" in sys.argv
	args = [a for a in sys.argv[1:] if a != "--apply"]
	out_dir = Path(args[0]) if args else ROOT / "hub/art/coins/variants/glow_2026-11-06"
	out_dir.mkdir(parents=True, exist_ok=True)
	pairs = []
	for path in secret_files():
		# --apply: исходник — копия без свечения в BACKUP (повторный запуск не светит дважды), запись — поверх игровой монеты.
		backup = BACKUP / path.relative_to(ROOT)
		if apply and not backup.exists():
			backup.parent.mkdir(parents=True, exist_ok=True)
			backup.write_bytes(path.read_bytes())
		source = backup if backup.exists() else path
		before = Image.open(source).convert("RGBA")
		after = glow(before)
		after.save(path if apply else out_dir / path.name)
		pairs.append((before, after))
		print("✓", path.relative_to(ROOT))
	compare(pairs, out_dir / "_compare.png")


if __name__ == "__main__":
	main()
