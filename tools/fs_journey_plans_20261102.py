"""Ответы операторского стенда только по изображениям, прочитанным Codex 02.11.

Не меняет состояние игры: пишет план, который fs_player_journey выполняет обычными кнопками.
Неизвестная карта остаётся ждать чтения полного изображения и отдельного ответа оператора.
Тексты сохранены в games/four_souls/art/card_texts.json; награды включают напечатанные души.
"""
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'build/fs_acceptance' / sys.argv[1]
seen = set()
reward_boost = {}
deadline = time.monotonic() + 10800
while time.monotonic() < deadline:
    if (folder / 'ui-summary.json').exists():
        summary = json.loads((folder / 'ui-summary.json').read_text(encoding='utf-8'))
        print('Стенд закончен; ошибок:', summary['errors'],
              'финальная фаза:', summary['final']['phase'], flush=True)
        break
    request = folder / 'request.json'
    try:
        data = json.loads(request.read_text(encoding='utf-8'))
    except (FileNotFoundError, json.JSONDecodeError):
        time.sleep(0.5)
        continue
    key = (data['step'], data['effect']['card'], data['effect']['kind'])
    if key in seen:
        time.sleep(0.5)
        continue
    seen.add(key)
    effect = data['effect']
    card = int(effect['card'])
    owner = int(effect['owner'])
    view = data['view']
    plan = None
    def operation(op, amount=1, target=owner, item=0):
        return dict(op=op, amount=amount, target=target, item=item)
    if effect['kind'] == 'reward':
        if card in (439, 466, 354, 355):
            plan = [operation('loot', 2)]
        elif card in (345, 421):
            plan = [operation('loot', 2), operation('souls')]
        elif card in (264, 420, 456):
            # Начиная с исправления264 награда смерти открывается только на смертельной6.
            # Спасение выдаёт сокровище автоматически и не запрашивает этот план.
            plan = [operation('treasure'), operation('souls')]
        elif card in (352, 384, 436, 462, 441, 370, 418):
            # Необязательную кражу418 можно не применять.
            plan = [operation('coins', {352: 3, 384: 6, 436: 4, 462: 7, 441: 3, 370: 6, 418: 4}[card])]
        elif card == 428:
            plan = [operation('coins', 5), operation('souls')]
        elif card == 407:
            lethal = 0
            for monster in view['monsters']:
                while monster:
                    if int(monster['id']) == 407:
                        lethal = int(monster.get('lethal_attack_roll', 0))
                    monster = monster.get('under', {})
            plan = [dict(roll=True), dict(operation('coins', 'last_roll'), multiplier=2 if lethal == 6 else 1)]
        elif card in (423, 409):
            plan = [operation('coins')]
        elif card in (346, 417, 427):
            # Необязательный просмотр чужой руки417 можно не применять.
            plan = [operation('loot')]
        elif card == 280:
            plan = [operation('loot', 3)]
        elif card == 424:
            plan = [operation('expand_monsters'), operation('coins', 3)]
        elif card == 369:
            plan = [operation('damage', target=seat) for seat in range(len(view['players']))]
            plan += [operation('loot')]
        elif card == 395:
            plan = [operation('skip_turn', target=int(view['current'])),
                    operation('loot', 3), operation('souls')]
        elif card == 414:
            plan = [operation('discard_loot') for _ in range(int(view['players'][owner]['hand_count']))]
            plan += [operation('coins'), operation('souls')]
    elif effect['kind'] == 'event' and card == 711:
        # Допустимый выбор: не возвращать ни одного монстра из сброса.
        plan = [operation('extra_attack', target=int(view['current']))]
    elif effect['kind'] == 'event' and card in (706, 709, 724):
        plan = [operation('attach_curse', target=(owner + 1) % len(view['players']))]
    elif effect['kind'] == 'event' and card == 716:
        coins = [int(player['coins']) for player in view['players']]
        target = coins.index(max(coins))
        plan = [operation('coins', -coins[target], target)] if coins[target] else []
    elif effect['kind'] == 'event' and card == 730:
        plan = [dict(roll=True),
                dict(operation('peek_monster', 3), when_roll=[1, 2, 3]),
                dict(operation('extra_attack'), when_roll=[1, 2, 3]),
                dict(operation('damage'), when_roll=[4, 5, 6])]
    elif effect['kind'] == 'event' and card == 727:
        # Стенд помнит ручное требование727 и выбирает верх колоды настоящей кнопкой.
        plan = [dict(roll=True),
                dict(operation('extra_attack'), when_roll=[1, 2]),
                dict(operation('loot', 3), when_roll=[3, 4]),
                dict(operation('treasure'), when_roll=[5, 6])]
    elif effect['kind'] == 'event' and card == 703:
        plan = [dict(roll=True), dict(operation('damage', 3), when_roll=[1]),
                dict(operation('discard_loot'), when_roll=[2, 3]),
                dict(operation('discard_loot'), when_roll=[2, 3]),
                dict(operation('coins', 7), when_roll=[4, 5]),
                dict(operation('treasure'), when_roll=[6])]
    elif effect['kind'] == 'event' and card == 700:
        plan = [dict(roll=True), dict(operation('loot'), when_roll=[1, 2]),
                dict(operation('coins', 3), when_roll=[3, 4]),
                dict(operation('damage', 2), when_roll=[5, 6])]
    elif effect['kind'] == 'event' and card == 719:
        plan = [dict(roll=True), operation('damage'),
                dict(operation('loot'), when_roll=[3, 4]),
                dict(operation('treasure'), when_roll=[5, 6])]
    elif effect['kind'] == 'loot' and card == 476:
        plan = [operation('coins'), dict(roll=True)]
    elif effect['kind'] == 'loot' and card == 506:
        plan = [dict(roll=True),
                dict(operation('self_give', target=(owner + 1) % len(view['players'])), when_roll=[1, 2, 3]),
                dict(operation('coins', 5), when_roll=[4, 5, 6])]
    elif effect['kind'] == 'loot' and card == 544:
        plan = [operation('coins'), operation('recharge', item=0)]
    elif effect['kind'] == 'loot' and card == 528:
        plan = [operation('coins')]
        serial = int(data['turn_serial'])
        reward_boost[serial] = reward_boost.get(serial, 1) * 2
    if effect['kind'] == 'reward' and 'auto_reward' in effect:
        # Автоматический каталог сам выдаёт ресурсы. Оператор подтверждает только текст.
        if effect.get('requires_reward_roll') and 'reward_roll' not in effect:
            plan = [dict(roll=True)]
        elif not effect.get('death_text_done', False):
            plan = {
                418: [], 417: [],
                424: [operation('expand_monsters')],
                369: [operation('damage', target=seat) for seat in range(len(view['players']))],
                395: [operation('skip_turn', target=int(view['current']))],
                414: [operation('discard_loot') for _ in range(int(view['players'][owner]['hand_count']))],
            }.get(card)
            if card == 465:
                # Прочитано полное изображение: 2 урона распределяются произвольно.
                alive = next((i for i, monster in enumerate(view['monsters']) if int(monster['hp']) > 0), None)
                plan = [operation('monster_damage', 2, item=alive)] if alive is not None else [operation('damage', 2, (owner + 1) % len(view['players']))]
        elif not effect.get('post_reward_wait'):
            plan = []
        else:
            plan = None
    # У известных планов душа идёт последней: при возврате из вложенной Кармы
    # все ресурсы уже выданы, остаётся только подтвердить исходную награду.
    if effect['kind'] == 'reward' and 'auto_reward' not in effect and card in (264, 345, 395, 414, 420, 421, 428, 456) and effect.get('kept_as_soul'):
        plan = []
    if plan is None:
        print('НУЖНО ПРОЧИТАТЬ КАРТУ:', key, flush=True)
        continue
    # Ручная способность528: только напечатанные ресурсы награды, не души и не текст смерти.
    multiplier = reward_boost.get(int(data.get('turn_serial', -1)), 1)
    if effect['kind'] == 'reward' and multiplier > 1:
        for action in plan:
            if action.get('op') in ('coins', 'loot', 'treasure'):
                if isinstance(action.get('amount'), (int, float)) and action['amount'] > 0:
                    action['amount'] *= multiplier
                elif action.get('amount') == 'last_roll':
                    action['multiplier'] = action.get('multiplier', 1) * multiplier
    reply = folder / 'reply.json'
    temporary = reply.with_suffix('.tmp')
    temporary.write_text(json.dumps(plan, ensure_ascii=False), encoding='utf-8')
    os.replace(temporary, reply)
    print('План по проверенному изображению:', key, flush=True)
