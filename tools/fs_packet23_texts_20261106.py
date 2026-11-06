"""Полные тексты группы23, сверенные на texts23_0..9.png."""
import json
from pathlib import Path

COINS = {1: range(666, 672), 2: range(588, 597), 3: range(597, 612), 4: range(612, 621)}
TEXTS = {cid: f'Получи {amount}¢.' for amount, ids in COINS.items() for cid in ids}
TEXTS[675] = 'Если ты должен получить любое количество монет, вместо этого получи столько же +1¢. Брелок.'
assert len(TEXTS) == 40
root = Path(__file__).resolve().parents[1]
path = root / 'games/four_souls/art/card_texts.json'
data = json.loads(path.read_text(encoding='utf-8'))
cards = json.loads((root / 'games/four_souls/art/manifest.json').read_text(encoding='utf-8'))['cards']
for cid, text in TEXTS.items():
    data[str(cid)] = dict(name_ru=cards[cid]['name'].split('/')[0], type=cards[cid]['kind'], text=text,
                         stats={}, reward='', verified_image=True, verified='2026-11-06',
                         note='Прочитана полная область правил из texts23_0..9.png.')
path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
