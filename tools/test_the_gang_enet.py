"""Три настоящих процесса The Gang: приватность, захват фишки, пауза и возврат пати.
Запуск: bundled Python tools/test_the_gang_enet.py. Только свои процессы, Dummy, изолированный APPDATA.
"""
from pathlib import Path
import json
import os
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/the_gang_research/enet"
GODOT = Path("C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe")
OUT.mkdir(parents=True, exist_ok=True)
checks = 0
ids = {role: 0 for role in ("host", "alice", "bob")}
processes = {}
logs = []


def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)


def snapshot(role):
    try:
        return json.loads((OUT / f"{role}-snapshot.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def wait(role, predicate, description, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = snapshot(role)
        try:
            if predicate(state):
                return state
        except (KeyError, TypeError, IndexError):
            pass  # Снимок ещё не создан/обновляется; ждём именно нужную сторону.
        time.sleep(0.05)
    raise AssertionError(f"Ожидание {role}: {description}; последнее={snapshot(role)}")


def command(role, kind, arg=None):
    ids[role] += 1
    target = OUT / f"{role}-command.json"
    temp = target.with_suffix(".tmp")
    temp.write_text(json.dumps({"id": ids[role], "kind": kind, "arg": {} if arg is None else arg}), encoding="utf-8")
    os.replace(temp, target)
    if kind != "quit":
        wait(role, lambda s: s.get("command", -1) >= ids[role], kind)


def launch(role):
    # Убираются только артефакты данного именованного прогона, не игровые ресурсы.
    for suffix in ("command.json", "snapshot.json", "views.jsonl"):
        (OUT / f"{role}-{suffix}").unlink(missing_ok=True)
    env = os.environ.copy()
    env.update(TG_ROLE=role, TG_PORT="24883", APPDATA=str(OUT / f"profile-{role}"))
    log = (OUT / f"{role}.log").open("w", encoding="utf-8")
    logs.append(log)
    processes[role] = subprocess.Popen(
        [str(GODOT), "--headless", "--audio-driver", "Dummy", "--max-fps", "60", "--path", str(ROOT),
         "--script", "res://tests/tg_net_probe.gd"], cwd=ROOT, env=env,
        stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)


try:
    launch("host")
    wait("host", lambda s: s.get("mode") == "enet", "хост открыт")
    launch("alice")
    wait("host", lambda s: s.get("members") == 2, "Alice вошла")
    launch("bob")
    wait("host", lambda s: s.get("members") == 3, "Bob вошёл")
    command("host", "setting", {"key": "turn_time", "value": 30})
    command("host", "start")
    states = {r: wait(r, lambda s: s.get("view", {}).get("phase") == "rank", "стол") for r in ids}
    server = states["host"]
    for role, state in states.items():
        view = state["view"]
        seat = int(view["seat"])
        check(view["hand"] == server["audit_hands"][seat], f"{role}: только своя рука")
        check("hands" not in view and not view["result"], f"{role}: чужие руки скрыты")
        check(view["turn_total"] == 30, f"{role}: срок раунда")
    command("alice", "view_seat", {"seat": 0})
    check(snapshot("alice")["view"]["seat"] != 0, "Сетевой клиент не переключает чужой экран")
    command("alice", "take", {"value": 1})
    wait("host", lambda s: s["view"]["chips"][1] == 1, "Alice взяла1")
    command("bob", "take", {"value": 1})
    for role in ids:
        state = wait(role, lambda s: s["view"]["chips"] == [0, 0, 1], "Bob забрал1")
        check(state["view"]["chips"] == [0, 0, 1], f"{role}: сериализация захвата фишки")
    command("host", "pause", True)
    for role in ids:
        wait(role, lambda s: s["view"].get("game_paused"), "пауза")
    command("alice", "take", {"value": 2})
    check(snapshot("host")["view"]["chips"] == [0, 0, 1], "Действие на паузе отвергнуто")
    command("host", "pause", False)
    for role in ids:
        wait(role, lambda s: not s["view"].get("game_paused"), "снята пауза")
    command("alice", "take", {"value": 2})
    wait("host", lambda s: s["view"]["chips"] == [0, 2, 1], "Alice взяла2")
    command("host", "take", {"value": 3})
    for role in ids:
        state = wait(role, lambda s: s["view"]["round_no"] == 2, "флоп")
        check(state["view"]["history"][0] == [3, 2, 1], f"{role}: история первого раунда")
        check(len(state["view"]["community"]) == 3, f"{role}: три общих карты")
    command("bob", "leave")
    wait("host", lambda s: bool(s.get("disconnected")), "дисконнект")
    command("bob", "join")
    returned = wait("bob", lambda s: s.get("in_game") and s.get("view", {}).get("round_no") == 2, "возврат на прежнее место")
    check(returned["view"]["hand"] == server["audit_hands"][2], "Возврат сохраняет прежнюю руку")
    command("host", "party")
    for role in ids:
        state = wait(role, lambda s: not s.get("in_game") and s.get("party") == "", "возврат к выбору игры")
        check(state["mode"] == "enet", f"{role}: соединение пати сохранено")
    report = {"checks": checks, "errors": 0, "scope": "3 настоящих ENet-процесса, базовый сценарий"}
    (OUT / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"THE GANG ENET: {checks} проверок, 0 ошибок")
finally:
    for role, process in processes.items():
        if process.poll() is None:
            try:
                command(role, "quit")
            except (AssertionError, OSError):
                pass
    for process in processes.values():
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.terminate()
    for log in logs:
        log.close()
