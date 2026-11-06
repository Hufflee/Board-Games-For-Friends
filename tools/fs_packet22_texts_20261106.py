"""Тексты группы22 из texts22_0..9.png. Монеты сверены по каждому изображению."""
import json
from pathlib import Path

COINS = {
    1: [549, 550, 575, 576, 577],
    2: [535, 536, 555, 556, 557, 585, 586, 587],
    3: [485, 486, 487, 488, 489, 490, 537, 538, 558, 559, 560, 561],
    4: [491, 492, 493, 494, 539, 540, 562, 563],
    5: [522, 583],
}
TEXTS = {cid: f'Получи {amount}¢.' for amount, ids in COINS.items() for cid in ids}
TEXTS.update({
    500: 'Прибавь или отними 1 от числа в тексте эффекта карты в игре или разыгранной добычи до конца хода. Число не может стать меньше 1 или больше 6.',
    502: 'Когда это входит в игру, положи золотой жетон на другой не-вечный предмет под твоим контролем. Это имеет способности других предметов с золотыми жетонами. Брелок.',
    514: 'Предотврати весь небоевой урон, который ты должен получить. Брелок.',
    534: 'В начале своего хода брось кубик. 4–6: это становится копией другого не-вечного предмета до конца хода. Брелок.',
    564: 'С разыгрыванием этого выбери предмет. Это копирует одну из поворотных способностей того предмета.',
})
assert len(TEXTS) == 40
root = Path(__file__).resolve().parents[1]
path = root / 'games/four_souls/art/card_texts.json'
data = json.loads(path.read_text(encoding='utf-8'))
cards = json.loads((root / 'games/four_souls/art/manifest.json').read_text(encoding='utf-8'))['cards']
for cid, text in TEXTS.items():
    data[str(cid)] = dict(name_ru=cards[cid]['name'].split('/')[0], type=cards[cid]['kind'], text=text,
                         stats={}, reward='', verified_image=True, verified='2026-11-06',
                         note='Прочитана полная область правил из texts22_0..9.png.')
path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
