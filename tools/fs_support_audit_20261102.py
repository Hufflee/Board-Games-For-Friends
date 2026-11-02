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
