"""Вырезает карты двух томов из PDF владельца. Запуск из корня: python tools/import_unmatched_art.py."""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image


SOURCES = Path('build/unmatched_sources')
ART = Path('games/unmatched/art')
DPI = 144
BACK_WIDTH = 336
CARD_QUALITY = 75
GARDENS_SOURCE = 'Maps_PNP_А4.pdf'
GARDENS_SIZE = (1337, 866)
GARDENS_PAGE = 11
REFERENCE_CARDS = {
	'bigfoot': (1, 67, 4), 'robin_hood': (1, 69, 0),
    'alice': (1, 67, 3), 'arthur': (1, 67, 7), 'medusa': (1, 67, 8), 'sinbad': (1, 69, 1),
    'yennenga': (2, 27, 3), 'achilles': (2, 27, 4),
    'bloody_mary': (2, 27, 5), 'sun_wukong': (2, 27, 6), 'actions': (1, 70, 0),
}
WIDTH = {1: 180.0, 2: 178.583}
HEIGHT = 249.449
X = {1: (13.465, 207.638, 401.811), 2: (18.425, 208.346, 398.268)}
Y = {1: (809.291, 545.669, 282.047), 2: (806.457, 545.669, 284.882)}
DECKS = {
	'bigfoot': (1, 7, 3), 'robin_hood': (1, 61, 0),
    'alice': (1, 1, 0),
    'arthur': (1, 41, 0),
    'medusa': (1, 47, 3),
    'sinbad': (1, 53, 6),
    'yennenga': (2, 1, 0),
    'achilles': (2, 7, 3),
    'bloody_mary': (2, 13, 6),
    'sun_wukong': (2, 21, 0),
}
BACK_PAGES = {
	'bigfoot': 10, 'robin_hood': 62,
    'alice': 2, 'arthur': 42, 'medusa': 50, 'sinbad': 56,
    'yennenga': 2, 'achilles': 10, 'bloody_mary': 16, 'sun_wukong': 22,
}
# Печатный порядок PnP отличается от стабильных ID уже автоматизированных колод.
PNP_ORDER = {
    'bigfoot': [*range(24, 27), *range(27, 30), *range(22, 24), *range(20, 22),
                *range(17, 20), *range(14, 17), *range(11, 14), *range(9, 11),
                *range(6, 9), *range(3, 6), *range(0, 3)],
    'robin_hood': [*range(27, 30), *range(24, 27), *range(22, 24), *range(20, 22),
                  *range(18, 20), *range(14, 18), *range(12, 14), *range(9, 12),
                  *range(6, 9), *range(3, 6), *range(0, 3)],
}
# Прямоугольники измерены на превью страниц, приведённых к 538 × 761.
TOKENS = {
    'alice': (1, (18, 17, 130, 82), 90),
    'arthur': (1, (18, 92, 130, 157), 90),
    'medusa': (1, (18, 166, 130, 232), 90),
    'sinbad': (1, (18, 241, 130, 306), 90),
    'jabberwock': (1, (460, 101, 515, 157), 0),
    'merlin': (1, (460, 176, 515, 232), 0),
    'harpy': (1, (306, 102, 360, 157), 0),
    'porter': (1, (154, 101, 208, 157), 0),
    'achilles': (2, (266, 20, 379, 85), 90),
    'bloody_mary': (2, (389, 20, 502, 85), 90),
    'sun_wukong': (2, (266, 94, 379, 159), 90),
    'yennenga': (2, (389, 94, 502, 159), 90),
    'patroclus': (2, (196, 23, 251, 78), 0),
    'archer_2': (2, (40, 23, 96, 78), 0),
    'archer_1': (2, (363, 184, 418, 240), 0),
    'clone': (2, (41, 99, 96, 155), 0),
}


def render(pdf, page, path):
    subprocess.run([
        'pdftoppm', '-r', str(DPI), '-f', str(page), '-l', str(page),
        '-singlefile', '-png', str(pdf), str(path.with_suffix('')),
    ], check=True, capture_output=True)


def card_box(volume, cell):
    x = X[volume][cell % 3]
    y = 841.89 - Y[volume][cell // 3]
    return tuple(round(p * DPI / 72) for p in (x, y, x + WIDTH[volume], y + HEIGHT))


def import_tokens(temporary):
    folder = ART / 'tokens'
    folder.mkdir(parents=True, exist_ok=True)
    sheets = {1: ('tokens.pdf', 1), 2: ('vol2_cards.pdf', 29)}
    for volume, (source, page) in sheets.items():
        png = temporary / f'tokens{volume}.png'
        render(SOURCES / source, page, png)
        with Image.open(png) as image:
            for token, (which, box, rotation) in TOKENS.items():
                if volume != which:
                    continue
                x1, y1, x2, y2 = box
                scaled = (x1 * image.width / 538, y1 * image.height / 761,
                          x2 * image.width / 538, y2 * image.height / 761)
                portrait = image.crop(tuple(round(p) for p in scaled)).rotate(rotation, expand=True)
                portrait.convert('RGB').save(folder / f'{token}.webp', quality=88)


def import_cards(temporary):
    manifest_path = ART / 'cards' / 'sources.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
    for hero, (volume, first_page, offset) in DECKS.items():
        folder = ART / 'cards' / hero
        folder.mkdir(parents=True, exist_ok=True)
        manifest[hero] = []
        for index in range(30):
            source_index = PNP_ORDER.get(hero, range(30))[index]
            sheet, cell = divmod(offset + source_index, 9)
            page = first_page + sheet * 2
            png = temporary / f'cards{volume}_{page}.png'
            if not png.exists():
                render(SOURCES / f'vol{volume}_cards.pdf', page, png)
            filename = f'{index + 1:02}.webp'
            with Image.open(png) as image:
                card = image.crop(card_box(volume, cell)).convert('RGB')
                encoded = temporary / filename
                card.save(encoded, quality=CARD_QUALITY, method=6)
                encoded.replace(folder / filename)
            manifest[hero].append({'file': filename, 'page': page, 'cell': cell + 1})
    manifest_path.write_text(
        json.dumps(manifest, indent=2) + '\n', encoding='utf-8',
    )


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--cards-only', action='store_true', help='Обновить только лицевые стороны карт.')
    modes.add_argument('--backs-only', action='store_true', help='Обновить только рубашки колод.')
    modes.add_argument('--gardens-only', type=Path, help='Извлечь Висячие сады из файла Maps_PNP_А4.pdf.')
    modes.add_argument('--references-only', action='store_true', help='Извлечь карточки героев и памятку.')
    args = parser.parse_args()
    if args.gardens_only:
        import_gardens(args.gardens_only)
        return
    with tempfile.TemporaryDirectory(dir=SOURCES) as scratch:
        temporary = Path(scratch)
        if args.references_only:
            import_references(temporary)
            return
        if not args.backs_only:
            import_cards(temporary)
        if args.cards_only:
            return
        import_backs(temporary)
        if args.backs_only:
            return
        boards = ART / 'boards'
        boards.mkdir(parents=True, exist_ok=True)
        for side in ('a', 'b'):
            png = temporary / f'board_{side}.png'
            render(SOURCES / f'vol1_board_{side}.pdf', 1, png)
            with Image.open(png) as image:
                image.convert('RGB').save(boards / f'vol1_{side}.webp', quality=91, method=5)
        if (SOURCES / GARDENS_SOURCE).is_file():
            import_gardens(SOURCES / GARDENS_SOURCE)
        import_tokens(temporary)
        import_references(temporary)


def import_backs(temporary):
    folder = ART / 'backs'
    folder.mkdir(parents=True, exist_ok=True)
    for hero, page in BACK_PAGES.items():
        volume = DECKS[hero][0]
        png = temporary / f'back_{volume}_{page}.png'
        render(SOURCES / f'vol{volume}_cards.pdf', page, png)
        with Image.open(png) as image:
            card = image.crop(card_box(volume, 0)).convert('RGB')
            height = round(card.height * BACK_WIDTH / card.width)
            card = card.resize((BACK_WIDTH, height), Image.Resampling.LANCZOS)
            encoded = temporary / f'{hero}.webp'
            card.save(encoded, quality=CARD_QUALITY, method=6)
        encoded.replace(folder / encoded.name)


def import_gardens(pdf):
    from pypdf import PdfReader

    page = PdfReader(pdf).pages[GARDENS_PAGE - 1]
    images = list(page.images)
    if len(images) != 1 or images[0].image.size != (2750, 1780):
        raise ValueError('Страница 11 должна содержать исходное изображение поля 2750 × 1780.')
    folder = ART / 'boards'
    folder.mkdir(parents=True, exist_ok=True)
    board = images[0].image.convert('RGB').resize(GARDENS_SIZE, Image.Resampling.LANCZOS)
    board.save(folder / 'gardens.webp', quality=88, method=6)


def import_references(temporary):
    folder = ART / 'references'
    folder.mkdir(parents=True, exist_ok=True)
    for name, (volume, page, cell) in REFERENCE_CARDS.items():
        png = temporary / f'references_{volume}_{page}.png'
        if not png.is_file():
            render(SOURCES / f'vol{volume}_cards.pdf', page, png)
        with Image.open(png) as image:
            card = image.crop(card_box(volume, cell)).convert('RGB')
            card.save(folder / f'{name}.webp', quality=87, method=6)


if __name__ == '__main__':
    main()
