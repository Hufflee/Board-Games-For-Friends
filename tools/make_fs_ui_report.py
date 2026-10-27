"""Собирает таблицу «действие — ожидание — результат» из настоящего UI-прогона."""
from collections import Counter
import json
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--run", default="resumed26")
parser.add_argument("--output", default="FS_UI_TEST_REPORT_2026-10-26.md")
args = parser.parse_args()
SOURCE = ROOT / "build/fs_acceptance" / args.run
summary = json.loads((SOURCE / "ui-summary.json").read_text(encoding="utf-8"))
rows = [json.loads(line) for line in (SOURCE / "ui-actions.jsonl").read_text(
    encoding="utf-8").splitlines() if line.strip()]
final = summary["final"]
counts = Counter(row["action"] for row in rows)
winner = int(final["winner"])
finished = final["phase"] == "game_over" and winner >= 0
passed = sum(row["ok"] for row in rows)
text = f"""# Айзек: UI-прогон 26.10.2026

Результат: {'партия завершена' if finished else 'партия не завершена'}. Раунд {final['round_no']}, шагов сценария {summary['steps']}, записанных проверок {len(rows)}, успешных {passed}, ошибок сценария {summary['errors']}.
Победитель: {final['players'][winner]['name'] if winner >= 0 else 'нет'}. Души игроков: {[player['souls'] for player in final['players']]}.

Godot 4.7.2, D3D12/GTX1650, 1280×720, --audio-driver Dummy, отдельный APPDATA build/fs_resume_ui_profile. tests/fs_player_journey.gd запускает обычное меню, локальное лобби и стол на двух игроков. Розыгрыши, покупки, атаки, пауза и броски выполняются событиями мыши; переключатель hotseat и значения ручных операций выбираются через UI. Engine.time_scale=3 ускоряет ожидание анимаций. HP, души, состав колод, результаты кубиков и ресурсы не подменялись.

## Границы результата

- Это полный проход игрового цикла до победы, а не проверка всех 913 карт или всех сочетаний эффектов. Обычные монеты/брелоки/потерянная душа автоматизированы; награды и сложные события выполнялись вручную по показанному русскому тексту. Условные пассивы всех встреченных монстров и предметов не покрыты этим сценарием, поэтому полное соответствие партии всем текстам карт не подтверждено.
- Изменённая Проклятая опухоль и переброс Осколком кубика дополнительно проверены подготовленными состояниями: tests/test_fs_pending_reward.gd — 16/0. Отдельный tests/test_fs_reroll_ui.gd — 10/0: настоящий жест исходного владельца, один результат, окно ответов и возврат эффекта автору Осколка. Это подготовленный сценарий, не естественная раздача в основной партии.
- Повторные правила: test_four_souls 7497/0, test_fs_audit_fixes_20261025 80/0, test_fs_responses 19/0, test_fs_combat_hp 21/0, test_fs_full_game 62776/0. Эти тесты не заменяют UI-проверку сложных карт.
- Сетевая партия ENet описана отдельно в docs/FS_ENET_TEST_REPORT_2026-10-25.md. Этот прогон локальный; Steam не проверен.
- Первые короткие попытки сценария выявили выбор скрытого канала чата вместо hotseat-переключателя. Исправлен тестовый выбор видимого OptionButton; приведённая ниже таблица относится к последнему запуску.
- При завершении процессов остаются сообщения об освобождении ресурсов: основная партия — 4 ObjectDB и 2 ресурса, подготовленный переброс — 12 ObjectDB и 6 ресурсов. Во время действий ошибок скриптов не было. Причина сообщений при завершении отдельно не устранена и требует проверки; «443/0» относится к проверкам сценария.

## Частота действий

| Действие | Количество |
|---|---:|
"""
for action, count in counts.items():
    text += f"| {action} | {count} |\n"
text += "\n## Действие — ожидаемый результат — настоящий результат\n\n"
text += "| Шаг | Действие | Ожидаемый результат | Настоящий результат | Итог |\n"
text += "|---:|---|---|---|---|\n"
for row in rows:
    cells = [str(row["step"]), row["action"], row["expected"], row["actual"],
             "OK" if row["ok"] else "Ошибка"]
    text += "| " + " | ".join(cell.replace("|", "\\|").replace("\n", " ") for cell in cells) + " |\n"
text += "\nДоказательства: build/fs_acceptance/resumed26/ui-actions.jsonl, ui-summary.json, start.png, finish.png; консоль build/fs-resume-ui.log.\n"
manifest = json.loads((ROOT / "games/four_souls/art/manifest.json").read_text(encoding="utf-8"))
text += "\n## Основания душ победителя\n\n"
for soul in final["players"][winner]["souls_cards"] if winner >= 0 else []:
    card = manifest["cards"][int(soul["id"])]
    text += f"- №{int(soul['id'])}: {card['name'].split('/')[0]} — {soul['value']} душа.\n"
if args.run == "post-passive-fixes26h":
    text = text.replace("## Границы результата", "Этот результат подтверждает цикл интерфейса до победы. Бой Тишины в записанной партии прошёл без части обязательных условий; это найденная ошибка, исправленная отдельными проверками после прогона, а не подтверждение полной корректности партии.\n\n## Границы результата")
    text = text.replace("build/fs_resume_ui_profile", f"build/fs_acceptance/{args.run}/profile")
    text = text.replace("7497/0", "8214/0").replace("62776/0", "112053/0")
    text = text.replace("build/fs_acceptance/resumed26", f"build/fs_acceptance/{args.run}")
    text = text.replace("build/fs-resume-ui.log", "build/fs-passive-journey-h.log")
    start = text.index("- Первые короткие попытки")
    end = text.index("## Частота действий", start)
    text = text[:start] + """- Предыдущие попытки A/B сохранены. Проверка конечной суммы при штрафе была неверна: отложенный Проглоченный пенни возвращал списанную монету. Отдельная регрессия теперь проверяет списание до пассива и возврат после; оба штрафа одновременной смерти проверены настоящими кнопками.
- Попытка C остановлена и не засчитывается: оператор пропустил души на наградах465/415/429; дополнительно harness однажды прочитал частичный JSON. Добавлены проверка полноты этих наград, ожидание полного JSON и атомарная запись ответов. Новый прогон начинается с меню без переноса её состояния.
- Попытка D выявила исчезновение панели награды после пассива от ручного урона Бомбанытика. Исправление отдельно проверено: правила24/0, UI26/0 (включая жест броска после пассива), ENet12/0. Текущая партия начата после исправления.
- Попытка E выявила рассогласование счётчика и карты души после Визуба: операция отрицательных душ не убирала карту. Добавлено целое уничтожение выбранной души (правила16/0, UI8/0). Затем E надолго повторяла бой с непосильным боссом; новая стратегия допускает верх колоды, текущая партия начата с нуля.
- Попытка F после длительного перерыва оставалась на паузе; это видно в failure.png. Операции Висельника были отклонены, harness затем завершился с ошибками. Перед продолжением добавлено снятие паузы. G не прошёл начальную проверку паузы; добавлено ожидание перехода из лобби. Текущая партия H начата с меню, без переноса состояния F/G.
- В этой партии встретилась Тишина281. Её обычные награды (два сокровища и две души) начислены полностью, но условия возрастающих бросков и ограничения урона ещё не работали. После прогона исправлены отдельно, HUSH TRAITS10/0 и HUSH UI12/0 (настоящий жест кубика, HP в интерфейсе и небоевой урон). Следовательно, завершение этого цикла не подтверждает корректный бой с Тишиной в самой записанной партии; полная партия после последней правки отдельно не повторялась.
- На момент H Засада715 и поиск Утопца после Пипа429 ещё не были подключены; они исправлены в следующем этапе. Прежнее описание отдельного постоянно неатакуемого слота было неверным: речь о ячейке вне текущего боя. Таблица H не подтверждает исправления следующих этапов.
- Предупреждения ObjectDB/resources при завершении остаются отдельной задачей; число проверок ниже относится к действиям сценария. Steam не проверялся.

""" + text[end:]
elif args.run != "resumed26":
    text = text.replace("build/fs_resume_ui_profile", f"build/fs_acceptance/{args.run}/profile")
    text = text.replace("build/fs_acceptance/resumed26", f"build/fs_acceptance/{args.run}")
    suffix = args.run[-1]
    text = text.replace("build/fs-resume-ui.log", f"build/fs-passive-journey-{suffix}.log")
    text = text.replace("7497/0", "8214/0").replace("62776/0", "128475/0")
    start = text.index("- Первые короткие попытки")
    end = text.index("## Частота действий", start)
    context_path = SOURCE / "report_context.json"
    context = json.loads(context_path.read_text(encoding="utf-8")) if context_path.exists() else {}
    notes = context.get("notes", ["Все сложные тексты карт и Steam этим прогоном не подтверждаются."])
    text = text[:start] + "\n".join("- " + note for note in notes) + "\n\n" + text[end:]
    findings_path = SOURCE / "semantic-findings.json"
    findings = json.loads(findings_path.read_text(encoding="utf-8")) if findings_path.exists() else []
    if findings:
        failed = sum(not finding["ok"] for finding in findings)
        still_open = sum(not finding["ok"] and finding.get("status") != "fixed_after_run" for finding in findings)
        warning = f"Отдельная сверка семантики карт: {len(findings)} наблюдений, {failed} расхождений в записанном прогоне; после отдельных исправлений открыты {still_open}. Ноль ошибок сценария не означает корректность партии по всем правилам."
        text = text.replace("## Границы результата", warning + "\n\n## Границы результата", 1)
        text += "\n## Дополнительные наблюдения семантики\n\n| Карта | Действие | Ожидается | Факт | Итог |\n|---|---|---|---|---|\n"
        verifications = []
        for finding in findings:
            cells = [str(finding["id"]) + " · " + finding["name"], finding["action"], finding["expected"], finding["actual"], "OK" if finding["ok"] else "Не пройдено"]
            text += "| " + " | ".join(str(cell).replace("|", "\\|").replace("\n", " ") for cell in cells) + " |\n"
            if finding.get("status") == "fixed_after_run":
                verifications.append("- " + str(finding["id"]) + ": " + finding.get("verification", "см. REVIEW_QUEUE.md"))
        if verifications:
            text += "\nИсправлено после прогона; исторические результаты строк не изменены:\n\n" + "\n".join(verifications) + "\n"
target = ROOT / "docs" / args.output
target.write_text(text, encoding="utf-8")
print(target, "rows", len(rows), "passed", passed, "finished", finished)
