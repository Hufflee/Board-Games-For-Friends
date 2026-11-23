"""Выбирает портреты из уже импортированных карт Шекспира и самураев.

Запуск из корня: python tools/import_unmatched_bard_portraits.py.
Квадраты центрируются под круглую маску игровой фишки.
"""

from pathlib import Path
import json

from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader


ART = Path("games/unmatched/art")
# Колода, номер карты, квадрат в пикселях импортированной иллюстрации.
PORTRAITS = {
    "tomoe": ("tomoe", 3, (83, 67, 291, 275)),
    "oda": ("oda", 14, (152, 38, 226, 112)),
    "samurai": ("oda", 7, (168, 72, 260, 164)),
    "witches": ("witches", 7, (151, 91, 251, 191)),
    "witch_0": ("witches", 7, (151, 91, 251, 191)),
    "witch_1": ("witches", 22, (126, 82, 258, 214)),
    "witch_2": ("witches", 16, (157, 67, 229, 139)),
    "shakespeare": ("shakespeare", 11, (148, 92, 234, 178)),
    "actor": ("shakespeare", 25, (174, 40, 214, 80)),
    "hamlet": ("hamlet", 1, (164, 26, 290, 152)),
    "rosencrantz": ("hamlet", 4, (220, 114, 332, 226)),
    "titania": ("titania", 9, (161, 79, 211, 129)),
    "oberon": ("titania", 5, (211, 68, 305, 162)),
}


def main() -> None:
    data = json.loads(Path('tools/unmatched_bard_samurai_cards.json').read_text(encoding='utf-8'))
    readers = {}
    cache = Path('build/unmatched_sources/batch_2026_11_22')
    for token, (hero, number, box) in PORTRAITS.items():
        with Image.open(ART / "cards" / hero / f"{number:02}.webp") as card:
            reference = card.convert('RGB')
        path = cache / f'portrait_native_{hero}_{number}.png'
        if path.exists():
            native = Image.open(path).convert('RGB')
        else:
            source = data[hero]['source']
            if source not in readers:
                readers[source] = PdfReader(Path('C:/Users/rabin/Downloads') / source)
            index = 1
            entry = None
            for row in data[hero]['cards']:
                if index == number:
                    entry = row
                    break
                index += row['count']
            candidates = []
            for embedded in readers[source].pages[entry['page'] - 1].images:
                image = embedded.image.convert('RGB')
                sample = image.resize(reference.size, Image.Resampling.BILINEAR)
                score = sum(ImageStat.Stat(ImageChops.difference(reference, sample)).mean)
                candidates.append((score, image))
            native = min(candidates, key=lambda candidate: candidate[0])[1]
            native.save(path)
        scaled = tuple(round(value * native.size[i % 2] / reference.size[i % 2]) for i, value in enumerate(box))
        portrait = native.crop(scaled).resize((256, 256), Image.Resampling.LANCZOS)
        portrait.save(ART / "tokens" / f"{token}.webp", quality=90, method=6)
        print(token, native.size, box, flush=True)


if __name__ == "__main__":
    main()
