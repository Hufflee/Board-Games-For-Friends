"""Импорт шести колод из PDF владельца и генерация печатных строк каталога; запуск из корня."""

import json
import subprocess
from pathlib import Path

from PIL import Image
from pypdf import PdfReader

DATA = Path(__file__).with_name('unmatched_bard_samurai_cards.json')
OUT = Path('build/unmatched_sources/batch_2026_11_22')
ART = Path('games/unmatched/art')
SOURCES = {'samurai': Path('C:/Users/rabin/Downloads/самураи.pdf'),
           'bard': Path('C:/Users/rabin/Downloads/шекспир офиц испр.pdf')}
DPI = 144


def page(source, number):
    path = OUT / f'full_{source}_{number}.png'
    if not path.exists():
        subprocess.run(['pdftoppm', '-r', str(DPI), '-f', str(number), '-l', str(number),
                        '-singlefile', '-png', str(SOURCES[source]), str(path.with_suffix(''))],
                       check=True, capture_output=True)
    return Image.open(path).convert('RGB')


def card(source, number, cell):
    image = page(source, number)
    # Позиции в долях страницы сохраняют физические размеры при другом MediaBox.
    x = (18.425, 208.346, 398.268)[(cell - 1) % 3]
    y = (35.433, 296.221, 557.008)[(cell - 1) // 3]
    return image.crop(tuple(round(v * 2) for v in (x, y, x + 178.583, y + 249.449)))


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, quality=78, method=6)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = json.loads(DATA.read_text(encoding='utf-8'))
    manifest_path = ART / 'cards' / 'sources.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    rows = []
    effects = []
    for hero, info in data.items():
        source = 'samurai' if hero in ('tomoe', 'oda') else 'bard'
        manifest[hero] = []
        rows.append('\t' + json.dumps(hero) + ': [')
        index = 1
        for entry in info['cards']:
            metadata = {k: entry[k] for k in ('syllables', 'ingredient') if k in entry}
            row = [index, entry['count'], entry['name'],
                   ['attack', 'defense', 'versatile', 'scheme'].index(entry['kind']),
                   ['hero', 'sidekick', 'any'].index(entry['fighter']), entry['value'] or 0, entry['boost']]
            if metadata:
                row.append(metadata)
            rows.append('\t\t' + json.dumps(row, ensure_ascii=False) + ',')
            effects.append(f'{hero}:{index:02} {entry["name"]}')
            image = card(source, entry['page'], entry['cell'])
            for _ in range(entry['count']):
                save(image, ART / 'cards' / hero / f'{index:02}.webp')
                manifest[hero].append({'file': f'{index:02}.webp', 'page': entry['page'], 'cell': entry['cell']})
                index += 1
        rows.append('\t],')
        reference = info['reference']
        save(card(source, reference['page'], reference['cell']), ART / 'references' / f'{hero}.webp')
        back = info['back']
        save(card(source, back['page'], back['cell']), ART / 'backs' / f'{hero}.webp')
    save(card('bard', 14, 5).rotate(90, expand=True), ART / 'references' / 'cauldron.webp')
    # Чары встроены в PDF отдельными изображениями: сохраняем полный печатный край,
    # без белых промежутков листа и погрешности разделения двух карт одной ячейки.
    reader = PdfReader(SOURCES['bard'])
    for index, (number, embedded) in enumerate([(14, 8), (14, 9), (15, 0), (15, 1), (15, 2), (15, 3)], 1):
        image = reader.pages[number - 1].images[embedded].image.convert('RGB').rotate(90, expand=True)
        image.thumbnail((720, 500), Image.Resampling.LANCZOS)
        save(image, ART / 'references' / f'enchantment_{index}.webp')
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (OUT / 'catalog_rows.gd.txt').write_text('\n'.join(rows) + '\n', encoding='utf-8')
    (OUT / 'effect_ids.txt').write_text('\n'.join(effects) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
