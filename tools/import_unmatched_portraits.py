"""Обновляет три фишки из иллюстраций русских PnP-карт, без текста и рамок."""

from pathlib import Path

from PIL import Image


ART = Path('games/unmatched/art')
# Квадратные фрагменты иллюстраций. На поле используется круглая маска UI.
PORTRAITS = {
    'loki': ('13', (80, 20, 330, 270)),
    'pandora': ('01', (95, 32, 270, 207)),
    'chupacabra': ('20', (110, 36, 304, 230)),
}


def main():
    for hero, (number, box) in PORTRAITS.items():
        with Image.open(ART / 'cards' / hero / f'{number}.webp') as image:
            portrait = image.crop(box).convert('RGB').resize((256, 256), Image.Resampling.LANCZOS)
            portrait.save(ART / 'tokens' / f'{hero}.webp', quality=90, method=6)


if __name__ == '__main__':
    main()
