"""Аудит меток auto и явных card-кейсов. Не заменяет поведенческую проверку карты.

Результат build/batch_20261102/support_audit.json. Упоминание ID в legacy не считается отдельным кейсом.
"""
import json
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / 'games/four_souls/art/card_support.json').read_text(encoding='utf-8'))
cases = {}
for path in (ROOT / 'tests/fs/cases').glob('*.gd'):
    for card in re.findall(r'"card"\s*:\s*(\d+)', path.read_text(encoding='utf-8')):
        cases.setdefault(card, []).append(path.name)
automatic = {key for key, value in data['cards'].items() if value['status'] == 'auto'}
# Это явный индекс реально исполняемых core-сценариев, не поиск любого числа в коде.
core_cases = {
    '7': dict(file='core_soul_control.gd', aspect='Чужие/свои души, перенос, порог3, уход источника, ценность2 и победа'),
    '475': dict(file='core_soul_control.gd', aspect='Физический лут становится душой и создаёт обязательные события'),
    '243': dict(file='core_chest.gd', aspect='Уничтожение, штраф смерти, отсутствие второго предмета, событие души'),
    '518': dict(file='core_counter_health.gd', aspect='Первое/второе уничтожение, штраф, предел HP и уход источника'),
    '867': dict(file='core_counter_health.gd', aspect='Свой старт/конец, третий жетон, лут3 и снятие бонуса HP'),
}
for cid in (348, 357, 361, 373, 384, 398, 402, 409, 412, 415, 422, 423, 425, 426, 427, 430, 431, 450, 451, 457, 458, 352, 310):
    core_cases[str(cid)] = dict(file='core_auto_rewards.gd', aspect='Напечатанная награда; у карты нет отдельной боевой способности')
core_cases['528'] = dict(file='core_reward_boost.gd', aspect='Монета, множитель ресурсов, отдельные души, истечение и бонус по таймеру')
for cid in [40, 120, 199, 476, 506, 544, 700, 703, 719, 727, 730, 716, 395, 414, 417, 424, 369, 822, 828, 834]:
    core_cases[str(cid)] = dict(file='core_automation_batch01.gd', aspect='Автоматические шаги, обязательный бросок, выбор допустимых целей, завершение')
for cid in [764, 766, 769, 770, 771, 772, 777, 781, 782, 796, 797, 798, 799, 800, 802, 806, 808, 809, 812, 818]:
    core_cases[str(cid)] = dict(file='core_automation_batch02.gd', aspect='Текст комнаты, границы событий, адресаты и снятие источника')
for cid in [497, 498, 499, 541, 512, 507, 508, 509, 510, 511, 515, 516, 517, 524, 525, 554, 531, 532, 542, 501]:
    core_cases[str(cid)] = dict(file='core_automation_batch03.gd', aspect='Текст каждой физической копии, допустимые цели, отказ чужому вводу, сохранение зон')
for cid in [567, 572, 573, 574, 643, 644, 645, 646, 655, 656, 657, 658, 659, 660, 661, 663, 664, 665, 650, 662]:
    core_cases[str(cid)] = dict(file='core_automation_batch04.gd', aspect='Отдельные физические копии, Золотая бомба3урона и Мегабатарейка')
for cid in range(621, 641):
    core_cases[str(cid)] = dict(file='core_automation_batch05.gd', aspect='Таро: цели, исходы броска, приватный просмотр, временные характеристики и условия уничтожения')
for cid in [477, 478, 479, 495, 496, 520, 521, 551, 565, 578, 579, 580, 581, 584, 648, 672, 673, 674, 529, 530]:
    core_cases[str(cid)] = dict(file='core_automation_batch06.gd', aspect='Все грани пилюль, руны, чужой обязательный выбор, физические превращения')
for cid in [469, 472, 504, 513, 519, 533, 543, 545, 547, 548, 552, 553, 568, 569, 641, 642, 679, 685, 686, 688]:
    core_cases[str(cid)] = dict(file='core_automation_batch07.gd', aspect='Бобы, отмена атаки, приватный выбор руки/души, сроки покупки/ответов и все грани руны')
for cid in [471, 473, 474, 505, 523, 526, 527, 546, 566, 570, 571, 582, 647, 651, 652, 653, 654, 677, 678, 687]:
    core_cases[str(cid)] = dict(file='core_automation_batch08.gd', aspect='Полный текст брелоков, обязательные броски, границы событий, чужие цели и сроки')
for cid in [16, 18, 24, 25, 26, 33, 36, 38, 39, 41, 45, 58, 62, 69, 76, 77, 79, 112, 174, 249]:
    core_cases[str(cid)] = dict(file='core_automation_batch09.gd', aspect='Сокровища: полный текст, первый бросок/вторая атака, первый урон, вход, оплата и передача')
for cid in [0, 6, 14, 15, 21, 84, 85, 86, 87, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99]:
    core_cases[str(cid)] = dict(file='core_automation_batch10.gd', aspect='Пакет40перваяполовина: таблицы, физическое уничтожение/душа, полный порядок колоды, активные выборы')
for cid in [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 113, 115, 116, 117, 118, 119, 121, 123]:
    core_cases[str(cid)] = dict(file='core_automation_batch10b.gd', aspect='Пакет40втораяполовина: общие яйца, чужие броски, платежи/сброс, дополнительные розыгрыши, открытие карт')
for cid in [697, 698, 699, 701, 702, 704, 710, 712, 713, 714, 715, 717, 718, 720, 721, 722, 725, 726, 728, 731, 732, 733, 734, 735, 738, 739, 740, 741, 742, 743, 779, 803, 804, 807, 810, 811, 813, 814, 815, 817]:
    core_cases[str(cid)] = dict(file="core_automation_batch11.gd", aspect="Таблицы событий, публичный/приватный выбор, комнаты и обязательные ограничения")
for cid in range(124, 164):
    core_cases[str(cid)] = dict(file="core_automation_batch12.gd", aspect="Полный текст124–163, чужой выбор, платные цены, четыре кубика, замены и предотвращение смерти")
for cid in range(164, 206):
    if cid not in [174, 199]:
        core_cases[str(cid)] = dict(file="core_automation_batch13.gd", aspect="Полные тексты, копия физической карты, голосование, платные цены, чужие выборы и замены добора")
for cid in range(206, 246):
    core_cases[str(cid)] = dict(file="core_automation_batch14.gd", aspect="Полные тексты206–245, копии на стеке, идентичность источника, замены бросков и обязательная атака")
for cid in range(246, 287):
    if cid != 249:
        core_cases[str(cid)] = dict(file="core_automation_batch15.gd", aspect="Полные тексты246–286, платные жетоны, совместная атака, штрафы и фамильяры")
for cid in range(287, 327):
    core_cases[str(cid)] = dict(file="core_automation_batch16.gd", aspect="Сорок текстов монстров, исходящий урон293, голоса324, чужие награды, отдельные стороны Догмы")
for cid in range(327, 367):
    core_cases[str(cid)] = dict(file="core_automation_batch17.gd", aspect="Полные тексты327–366, очереди напарников, одноразовые модификаторы, яйца и ограниченные атаки")
for cid in range(367, 409):
    if cid not in [369, 395]:
        core_cases[str(cid)] = dict(file="core_automation_batch18.gd", aspect="Сорок текстов, чужой выбор души, источник урона и объявление раскрытой атаки")
for cid in range(409, 452):
    if cid not in [414, 417, 424]:
        core_cases[str(cid)] = dict(file="core_automation_batch19.gd", aspect="Полные40текстов, случайная кража, общий иммунитет и размещение Утопца")
for cid in [452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 17, 19, 20, 22, 23, 27, 28, 29, 30, 31, 32]:
    core_cases[str(cid)] = dict(file="core_automation_batch20_monsters.gd" if cid in range(452, 467) else "core_automation_batch20_wildcards.gd" if cid in [467, 468] else "core_automation_batch20_treasures.gd", aspect="Полные тексты группы20, эффекты и физические зоны; спорные сочетания оставлены partial")
for evidence in core_cases.values():
    if not (ROOT / 'tests/fs/core' / evidence['file']).is_file():
        raise RuntimeError('Нет заявленного core-сценария: ' + evidence['file'])
covered = set(cases) | set(core_cases)
missing = sorted(automatic - covered, key=int)
observed = {}
sources = {}
for name in ('build/fs_passive_audit/runtime_after.json',
             'build/fs_passive_audit/followup/runtime_events.json'):
    path = ROOT / name
    if not path.exists():
        continue
    runtime = json.loads(path.read_text(encoding='utf-8'))
    sources[name] = dict(modified=datetime.fromtimestamp(path.stat().st_mtime).isoformat(),
                         mismatches=runtime.get('mismatches'), setup_errors=runtime.get('setup_errors'))
    for row in runtime.get('observations', []):
        if row.get('matches') is True:
            observed.setdefault(str(row['id']), []).append(dict(source=name, action=row['action']))
without_evidence = sorted(automatic - covered - set(observed), key=int)
report = dict(automatic=len(automatic), explicit_cases=len(automatic & covered),
              table_cases=len(automatic & set(cases)), core_cases=core_cases,
              missing=missing, cases=cases,
              observed_legacy=observed, runtime_sources=sources, without_evidence=without_evidence,
              note='Кейс/успешное наблюдение проверяет указанный аспект, не всю карту. Отсутствие записи не означает поломку.')
output = ROOT / 'build/batch_20261102/support_audit.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('auto:', len(automatic), 'с явным card-кейсом:', report['explicit_cases'], 'без:', len(missing))
print('Без явного кейса и наблюдения legacy:', len(without_evidence))
if '--verbose' in sys.argv:
    print('ID:', ', '.join(without_evidence))
