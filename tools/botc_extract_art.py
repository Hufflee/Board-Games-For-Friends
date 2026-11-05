"""Извлечение цветных эмблем ролей из альманахов TTS; английский текст не переносится в UI."""
import hashlib
import io
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, str(ROOT / 'build/botc_research/deps'))
import pymupdf
from PIL import Image, ImageDraw

OUT = ROOT / 'games/blood_on_the_clocktower/art/roles'
OUT.mkdir(parents=True, exist_ok=True)
source = (ROOT / 'games/blood_on_the_clocktower/logic/bc_data.gd').read_text(encoding='utf-8')
books = {'tb': 'trouble_brewing', 'bmr': 'bad_moon_rising', 'sv': 'sects_and_violets'}
manifest = []
for edition, book in books.items():
    document = pymupdf.open(ROOT / ('build/botc_research/' + book + '.pdf'))
    groups = re.findall(r'_add\(result, "' + edition + r'", "([a-z]+)", \[(.*?)\n\t\]\)', source, re.S)
    entries = [(kind, item[0], int(item[1])) for kind, group in groups
               for item in re.findall(r'\["([a-z_]+)", "[^"]*", "[^"]*", (\d+)\]', group)]
    for ordinal, (kind, role, page_number) in enumerate(entries):
        page = document[page_number - 1]
        right = ordinal == 0 or (ordinal - 1) % 2 == 1
        candidates = []
        for info in page.get_images(full=True):
            for rectangle in page.get_image_rects(info[0]):
                if rectangle.y0 < 100 and rectangle.width > 100 and (rectangle.x0 > 250) == right:
                    candidates.append(info[0])
        if not candidates:
            raise RuntimeError('Нет изображения жетона: ' + role)
        extracted = document.extract_image(candidates[0])
        token = Image.open(io.BytesIO(extracted['image'])).convert('RGB')
        icon = Image.new('RGBA', token.size)
        evil = kind in ['minion', 'demon']
        tint = (190, 102, 124) if evil else (119, 174, 213)
        for y in range(token.height):
            for x in range(token.width):
                r, g, b = token.getpixel((x, y))
                strength = r - max(g, b) if evil else b - max(r, g)
                alpha = max(0, min(255, (strength - 18) * 4))
                if alpha:
                    icon.putpixel((x, y), (*tint, alpha))
        bounds = icon.getbbox()
        if bounds is None:
            raise RuntimeError('Не выделена цветная эмблема: ' + role)
        icon = icon.crop(bounds)
        icon.thumbnail((192, 192))
        square = Image.new('RGBA', (208, 208))
        square.alpha_composite(icon, ((208 - icon.width) // 2, (208 - icon.height) // 2))
        path = OUT / (role + '.png')
        square.save(path)
        manifest.append({'id': role, 'book': book, 'page': page_number, 'xref': candidates[0],
                         'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
if len(manifest) != 72:
    raise RuntimeError(f'Ожидалось 72 эмблемы, найдено {len(manifest)}')
(OUT.parent / 'role_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
sheet = Image.new('RGB', (1200, 9 * 132), '#131e2b')
for i, row in enumerate(manifest):
    icon = Image.open(OUT / (row['id'] + '.png'))
    icon.thumbnail((92, 92))
    x, y = i % 8 * 150, i // 8 * 132
    sheet.paste(icon, (x + 26, y), icon)
    ImageDraw.Draw(sheet).text((x + 3, y + 96), row['id'], fill='#f0e3cc')
sheet.save(ROOT / 'build/shots/botc/role_icons.png')
print('Извлечены 72 эмблемы, манифест SHA256 сохранён')
