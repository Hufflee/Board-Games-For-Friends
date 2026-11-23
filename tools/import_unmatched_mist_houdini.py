"""Вырезает шесть русских колод из PDF владельца. Запуск из корня проекта."""

import argparse
import json
import subprocess
from pathlib import Path

from PIL import Image

ART = Path('games/unmatched/art')
OUT = Path('build/unmatched_sources/batch_2026_11_21')
SOURCES = [Path('C:/Users/rabin/Downloads/1. Том 1 + Туман + Бигфут и робин.pdf'),
           Path('C:/Users/rabin/Downloads/9 Джин и гудини.pdf')]
DECKS = {'dracula': (0, 13, 6), 'sherlock': (0, 21, 0),
         'invisible_man': (0, 27, 3), 'jekyll_hyde': (0, 33, 6),
         'genie': (1, 1, 0), 'houdini': (1, 4, 6)}
REFERENCES = {'dracula': (0, 67, 6), 'sherlock': (0, 67, 5),
              'invisible_man': (0, 69, 2), 'jekyll_hyde': (0, 69, 3),
              'genie': (1, 4, 3), 'houdini': (1, 4, 5)}
BACKS = {'dracula': (0, 16), 'sherlock': (0, 22), 'invisible_man': (0, 30),
         'jekyll_hyde': (0, 36), 'genie': (1, 8), 'houdini': (1, 10)}
MAGIC_ORDER = {
    'genie': [(2, 1, 0), (2, 1, 1), (2, 1, 2), (2, 1, 3), (2, 1, 4), (2, 1, 5),
              (3, 3, 0), (3, 3, 1), (3, 3, 2), (3, 3, 3), (3, 3, 4), (3, 3, 5)],
    'houdini': [(2, 5, 0), (2, 5, 1), (2, 5, 2), (2, 5, 3), (2, 5, 4), (2, 5, 5),
                (2, 5, 6), (2, 5, 7), (3, 7, 0), (3, 7, 1), (3, 7, 2), (1, 7, 4), (4, 7, 5)],
}


def page(source, number):
    path = OUT / f'full_{source}_{number}.png'
    if not path.exists():
        subprocess.run(['pdftoppm', '-r', '144', '-f', str(number), '-l', str(number),
                        '-singlefile', '-png', str(SOURCES[source]), str(path.with_suffix(''))],
                       check=True, capture_output=True)
    return Image.open(path).convert('RGB')


def crop(source, number, cell):
    x = ((13.465, 207.638, 401.811) if source == 0 else (18.425, 208.346, 398.268))[cell % 3]
    y = ((32.599, 296.221, 559.843) if source == 0 else (35.433, 296.221, 557.008))[cell // 3]
    width = 180.0 if source == 0 else 178.583
    return page(source, number).crop(tuple(round(p * 2) for p in (x, y, x + width, y + 249.449)))


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, quality=75, method=6)


def import_portraits():
    # Явные квадраты сохраняют положение лица после круглой маски игрового поля.
    portraits = {'dracula': ('dracula', 6), 'sister': ('dracula', 11),
                 'sherlock': ('sherlock', 18), 'watson': ('sherlock', 8),
                 'invisible_man': ('invisible_man', 24), 'jekyll_hyde': ('jekyll_hyde', 21), 'hyde': ('jekyll_hyde', 16),
                 'genie': ('genie', 13), 'houdini': ('houdini', 1), 'bess': ('houdini', 9)}
    boxes = {'jekyll_hyde': (80, 80, 300, 300), 'hyde': (94, 114, 234, 254), 'watson': (80, 35, 300, 255),
             'invisible_man': (100, 25, 310, 235), 'houdini': (95, 55, 305, 265)}
    for token, (hero, number) in portraits.items():
        with Image.open(ART / 'cards' / hero / f'{number:02}.webp') as image:
            box = boxes.get(token, (round(image.width * .20), round(image.height * .03),
                                    round(image.width * .96), round(image.height * .57)))
            save(image.crop(box), ART / 'tokens' / f'{token}.webp')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--portraits-only', action='store_true', help='Обновить только портреты фишек.')
    args = parser.parse_args()
    if args.portraits_only:
        import_portraits()
        return
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for hero, (source, first, offset) in DECKS.items():
        manifest[hero] = []
        magic = [(p, c) for count, p, c in MAGIC_ORDER.get(hero, []) for _ in range(count)]
        for index in range(30):
            sheet, cell = divmod(offset + index, 9)
            number = first + sheet * (2 if source == 0 else 1)
            if magic:
                number, cell = magic[index]
            save(crop(source, number, cell), ART / 'cards' / hero / f'{index + 1:02}.webp')
            manifest[hero].append({'file': f'{index + 1:02}.webp', 'page': number, 'cell': cell + 1})
        save(crop(*REFERENCES[hero]), ART / 'references' / f'{hero}.webp')
        source, number = BACKS[hero]
        save(crop(source, number, 0), ART / 'backs' / f'{hero}.webp')
    import_portraits()
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    path = ART / 'cards' / 'sources.json'
    full = json.loads(path.read_text(encoding='utf-8'))
    full.update(manifest)
    path.write_text(json.dumps(full, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
