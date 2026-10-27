"""Два реальных процесса ENet: бонусы, приватность, чужое действие и защита от повтора.
Подготовленные состояния разрешены только в тестовом скрипте и при FS_PASSIVE_FIXTURE=1.
"""
from pathlib import Path
import json
import os
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = "C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe"
RUN = "passive-fixes-" + str(int(time.time()))
OUT = ROOT / "build/fs_acceptance" / RUN
OUT.mkdir(parents=True)
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
processes = []
commands = {"host": 0, "client": 0}
results = []


def wait_for(predicate, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            if predicate():
                return
        except (FileNotFoundError, json.JSONDecodeError, KeyError, IndexError):
            pass
        time.sleep(0.05)
    raise TimeoutError("Сетевое состояние не достигнуто")


def snapshot(role):
    # Godot обновляет снимок каждый кадр: чтение может попасть между open и close.
    for _ in range(100):
        try:
            return json.loads((OUT / (role + "-snapshot.json")).read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            time.sleep(0.01)
    raise RuntimeError(f"Не удалось прочитать полный снимок {role}: {OUT}")


def send(role, kind, arg=None):
    commands[role] += 1
    temporary = OUT / (role + "-command.tmp")
    temporary.write_text(json.dumps({"id": commands[role], "kind": kind, "arg": arg}), encoding="utf-8")
    temporary.replace(OUT / (role + "-command.json"))
    wait_for(lambda: snapshot(role)["command"] == commands[role])


def check(condition, text):
    results.append({"check": text, "passed": bool(condition)})
    if not condition:
        raise AssertionError(text)


try:
    for role in ["host", "client"]:
        profile = OUT / (role + "-profile")
        profile.mkdir()
        env = dict(os.environ, APPDATA=str(profile), FS_ROLE=role, FS_RUN=RUN,
                   FS_PORT=str(port), FS_PASSIVE_FIXTURE="1")
        log = (OUT / (role + ".log")).open("w", encoding="utf-8")
        process = subprocess.Popen([GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                                    "--script", "res://tests/fs_enet_acceptance.gd"], env=env, stdout=log, stderr=log)
        processes.append((role, process, log))
        if role == "host":
            wait_for(lambda: snapshot("host")["members"] == 1)
    wait_for(lambda: snapshot("host")["members"] == 2)
    send("host", "start")
    wait_for(lambda: snapshot("client")["in_game"])
    send("host", "passive_fixture", "ownership")
    wait_for(lambda: snapshot("client")["view"]["players"][0]["attack"] == 2)
    host = snapshot("host")["view"]
    client = snapshot("client")["view"]
    check(host["players"][1]["hand"] == [476], "Глаз открывает руку клиента только хосту-владельцу")
    check("hand" not in client["players"][0], "Клиент без Глаза не получает руку хоста")
    send("client", "effect", {"op": "damage", "target": 0, "amount": 1})
    time.sleep(0.2)
    check(snapshot("host")["view"]["players"][0]["hp"] == 3, "Чужой клиент не исполняет эффект хоста")
    send("host", "effect", {"op": "give_item", "target": 1, "item": 0})
    wait_for(lambda: snapshot("client")["view"]["players"][1]["attack"] == 2)
    check([p["attack"] for p in snapshot("host")["view"]["players"]] == [1, 2], "Хост видит перенос бонуса")
    check([p["attack"] for p in snapshot("client")["view"]["players"]] == [1, 2], "Клиент видит тот же перенос бонуса")
    send("host", "effect", {"op": "destroy", "target": 0, "item": 0})
    wait_for(lambda: "hand" not in snapshot("host")["view"]["players"][1])
    check("hand" not in snapshot("host")["view"]["players"][1], "Уход Глаза закрывает руку на стороне владельца")
    send("host", "passive_fixture", "roll")
    wait_for(lambda: snapshot("client")["view"]["phase"] == "priority")
    send("client", "effect_roll")
    wait_for(lambda: snapshot("client")["view"]["players"][1]["coins"] == 6)
    check(snapshot("host")["view"]["players"][1]["coins"] == 6, "Пассив броска клиента вычислил хост")
    check(snapshot("client")["view"]["phase"] == "effect", "После пассива восстановлен исходный эффект клиента")
    send("client", "effect", {"op": "coins", "amount": 3, "target": 1})
    time.sleep(0.2)
    check(snapshot("host")["view"]["players"][1]["coins"] == 6, "Сетевой ручной повтор не удваивает автоматическую награду")
    send("host", "passive_fixture", "manual_resume")
    wait_for(lambda: snapshot("client")["view"]["players"][1]["coins"] == 3)
    send("client", "effect", {"op": "damage", "amount": 3, "target": 0})
    wait_for(lambda: snapshot("client")["view"].get("effect_pending", False))
    check(snapshot("host")["view"].get("effect_pending", False), "Обе стороны видят продолжение ручной награды после пассива")
    send("host", "effect", {"op": "coins", "amount": 6, "target": 1})
    time.sleep(0.2)
    check(snapshot("client")["view"]["players"][1]["coins"] == 3, "Хост не продолжает эффект клиента за него")
    send("client", "effect", {"op": "coins", "amount": 6, "target": 1})
    wait_for(lambda: snapshot("client")["view"]["players"][1]["coins"] == 9)
    view = snapshot("client")["view"]
    check(view["phase"] == "effect" and view["players"][0]["items"][0]["counters"] == 1,
          "Клиент продолжил награду, хост разрешил пассив ровно один раз")
    send("host", "passive_fixture", "soul_loss")
    wait_for(lambda: snapshot("client")["view"]["players"][1]["souls"] == 2)
    send("client", "effect", {"op": "destroy_soul", "target": 1, "item": 0})
    time.sleep(0.2)
    check(snapshot("host")["view"]["players"][1]["souls"] == 2, "Клиент не уничтожает душу чужим эффектом")
    send("host", "effect", {"op": "destroy_soul", "target": 1, "item": 0})
    wait_for(lambda: snapshot("client")["view"]["players"][1]["souls"] == 0)
    check(not snapshot("client")["view"]["players"][1]["souls_cards"], "Клиент видит удаление всей карты души вместе со стоимостью")
    send("host", "effect", {"op": "destroy_soul", "target": 1, "item": 0})
    time.sleep(0.2)
    check(snapshot("client")["view"]["players"][1]["souls"] == 0, "Повтор сетевого уничтожения не списывает душу дважды")
    send("host", "passive_fixture", "ambush")
    wait_for(lambda: snapshot("client")["view"].get("forced_deck_attacks") == 2)
    send("client", "end")
    time.sleep(0.2)
    check(snapshot("host")["view"]["current"] == 1, "Клиент не завершает ход до обязательных атак")
    send("client", "attack", {"slot": 0})
    time.sleep(0.2)
    check(snapshot("host")["view"]["phase"] == "turn", "Клиент не подменяет обязательную цель обычным монстром")
    send("client", "attack", {"slot": -1, "over": 0})
    wait_for(lambda: snapshot("host")["view"].get("forced_deck_attacks") == 1)
    wait_for(lambda: snapshot("client")["view"].get("forced_deck_attacks") == 1)
    check(True, "Обе стороны видят одну оставшуюся обязательную атаку")
    send("host", "passive_fixture", "peep")
    wait_for(lambda: snapshot("client")["view"].get("resolving", {}).get("spawn_card") == 282)
    send("client", "place_bloat", {"slot": 0})
    time.sleep(0.2)
    check(snapshot("host")["view"]["monsters"][0]["id"] == 429, "Клиент не накрывает ячейку текущего боя")
    send("host", "place_bloat", {"slot": 1})
    time.sleep(0.2)
    check(snapshot("client")["view"]["monsters"][1]["id"] == 451, "Хост не делает выбор за клиента")
    send("client", "place_bloat", {"slot": 1})
    wait_for(lambda: snapshot("client")["view"]["monsters"][1]["id"] == 282)
    check(snapshot("host")["view"]["monsters"][1]["under"]["id"] == 451, "Сетевое размещение сохраняет нижнюю карту")
    send("client", "place_bloat", {"slot": 1})
    time.sleep(0.2)
    check(len(snapshot("host")["view"]["monsters"]) == 2, "Повтор сетевого выбора не создаёт новую ячейку")
    send("host", "passive_fixture", "conquest")
    wait_for(lambda: snapshot("client")["view"].get("required_player_attacks") == 1)
    send("host", "attack_player", {"target": 1})
    time.sleep(0.2)
    check(snapshot("client")["view"]["phase"] == "turn", "Хост не объявляет PvP вместо клиента")
    send("client", "attack_player", {"target": 0})
    wait_for(lambda: snapshot("host")["view"]["stack"][-1]["kind"] == "player_attack")
    check(snapshot("host")["view"]["stack"][-1]["target"] == 0, "Цель PvP дошла до другого процесса")
    send("client", "roll")
    wait_for(lambda: snapshot("host")["view"]["stack"][-1]["kind"] == "roll")
    send("client", "roll")
    wait_for(lambda: snapshot("host")["view"]["phase"] == "death")
    wait_for(lambda: snapshot("client")["view"]["players"][0]["hp"] == 0)
    check(snapshot("client")["view"]["players"][0]["hp"] == 0, "Сетевой бросок4 нанёс защищавшемуся урон клиента")
    send("client", "death", {"item": -1, "loot": -1})
    time.sleep(0.2)
    check(snapshot("host")["view"]["phase"] == "death", "Клиент не платит чужой штраф")
    send("host", "death", {"item": -1, "loot": 475})
    wait_for(lambda: snapshot("client")["view"]["phase"] == "turn")
    check(snapshot("host")["view"]["current"] == 1, "После смерти защищавшегося ход клиента продолжается")
    send("host", "passive_fixture", "pride")
    wait_for(lambda: snapshot("client")["view"]["phase"] == "discard_target")
    send("host", "discard_target", {"target": 1})
    time.sleep(0.2)
    check(snapshot("client")["view"]["phase"] == "discard_target", "Только активный выбирает жертву Гордыни")
    send("client", "discard_target", {"target": 0})
    wait_for(lambda: snapshot("host")["view"]["phase"] == "priority")
    check(snapshot("host")["view"]["stack"][-1]["kind"] == "forced_discard", "Гордыня открыла сетевое окно ответов")
    send("host", "passive_fixture", "pride_discard")
    wait_for(lambda: snapshot("client")["view"]["phase"] == "forced_discard")
    check("hand" not in snapshot("client")["view"]["players"][0], "Выбирающий цель не видит руку жертвы")
    send("client", "forced_discard", {"item": 0})
    time.sleep(0.2)
    check(snapshot("host")["view"]["players"][0]["hand_count"] == 3, "Клиент не сбрасывает чужую руку")
    send("host", "forced_discard", {"item": 1})
    wait_for(lambda: snapshot("client")["view"]["players"][0]["hand_count"] == 2)
    send("host", "forced_discard", {"item": 0})
    wait_for(lambda: snapshot("client")["view"]["phase"] == "battle_roll")
    check(snapshot("host")["view"]["hand"] == [477], "Владелец сохранил именно выбранную третью карту")
    send("host", "passive_fixture", "expansion")
    wait_for(lambda: snapshot("client")["view"].get("resolving",{}).get("card") == 360)
    send("client", "effect", {"op":"expand_monsters", "amount":2})
    send("client", "effect_done")
    wait_for(lambda: len(snapshot("host")["view"]["monsters"]) == 4)
    wait_for(lambda: len(snapshot("client")["view"]["monsters"]) == 4)
    check(len(snapshot("client")["view"]["monsters"]) == 4, "Оба процесса видят расширенное поле Бластоцисты")
    for stage, value in [("global_horf",2),("global_keeper",4),("global_fatty",5)]:
        send("host", "passive_fixture", stage)
        wait_for(lambda: snapshot("client")["view"]["phase"] == "effect" and snapshot("client")["view"]["monsters"][0]["id"] == {"global_horf":440,"global_keeper":445,"global_fatty":439}[stage])
        before_roll = snapshot("host")["view"]["roll_no"]
        send("host", "effect_roll")
        time.sleep(0.15)
        check(snapshot("client")["view"]["roll_no"] == before_roll, "Хост не бросает за владельца ручной карты: " + stage)
        send("client", "effect_roll")
        wait_for(lambda: snapshot("host")["view"]["roll_no"] == before_roll + 1)
        send("client", "effect_roll")
        if stage == "global_horf":
            wait_for(lambda: snapshot("host")["view"]["players"][1]["hp"] == 3)
            check(snapshot("client")["view"]["players"][0]["hp"] == 5, "Хорф ранил именно клиента, бросившего2")
        elif stage == "global_keeper":
            wait_for(lambda: snapshot("host")["view"]["players"][1]["coins"] == 5)
            check(snapshot("client")["view"]["players"][0]["coins"] == 3, "Голова выдала2 монеты только клиенту с4")
        else:
            wait_for(lambda: snapshot("host")["view"]["phase"] == "forced_discard")
            send("host", "forced_discard", {"item":0})
            time.sleep(0.15)
            check(snapshot("client")["view"]["players"][1]["hand_count"] == 2, "Хост не выбирает карту клиента для Толстяка")
            send("client", "forced_discard", {"item":1})
            wait_for(lambda: snapshot("host")["view"]["phase"] == "effect")
            check(snapshot("client")["view"]["hand"] == [478], "Толстяк сохранил выбор карты и исходный эффект клиента")
finally:
    for role, process, log in processes:
        if process.poll() is None:
            try:
                send(role, "quit")
            except Exception:
                pass
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        log.close()
    (OUT / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
print("PASSIVE ENET:", len(results), "проверок, ошибок", sum(not row["passed"] for row in results), str(OUT))
