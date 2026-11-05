"""Два ENet-процесса: адресные выборы автоматической карты, приватность, чужие/устаревшие запросы."""
from pathlib import Path
import json
import os
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
GODOT = r"C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe"
RUN = "automation04-" + uuid.uuid4().hex
OUT = ROOT / "build/fs_acceptance" / RUN
OUT.mkdir(parents=True)
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
processes = []
commands = {"host": 0, "client": 0}
checks = 0


def wait(predicate, seconds=20):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            if predicate():
                return
        except (OSError, ValueError, KeyError, IndexError):
            pass
        time.sleep(.04)
    raise AssertionError("Превышено ожидание сетевого состояния")


def snapshot(role):
    for attempt in range(100):
        try:
            return json.loads((OUT / (role + "-snapshot.json")).read_text(encoding="utf-8"))
        except (json.JSONDecodeError, PermissionError):
            if attempt == 99:
                raise
            time.sleep(.01)


def send(role, kind, arg=None):
    commands[role] += 1
    temporary = OUT / (role + "-command.tmp")
    temporary.write_text(json.dumps({"id": commands[role], "kind": kind, "arg": arg}), encoding="utf-8")
    deadline = time.monotonic() + 3
    while True:
        try:
            temporary.replace(OUT / (role + "-command.json"))
            break
        except PermissionError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(.01)
    wait(lambda: snapshot(role)["command"] == commands[role])


def check(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)


def client_barrier():
    # Надёжный RPC чата идёт после действия по тому же каналу. Получение хостом
    # доказывает обработку предыдущего запроса, включая отклонённый.
    marker = "automation-barrier-" + uuid.uuid4().hex
    send("client", "chat", marker)

    def received():
        path = OUT / "host-chat.jsonl"
        return any(marker in str(json.loads(line).get("text", ""))
                   for line in path.read_text(encoding="utf-8").splitlines() if line)

    wait(received)


try:
    for role in ["host", "client"]:
        profile = OUT / (role + "_profile")
        profile.mkdir()
        env = dict(os.environ, APPDATA=str(profile), FS_ROLE=role, FS_RUN=RUN,
                   FS_PORT=str(port), FS_PASSIVE_FIXTURE="1")
        log = (OUT / (role + ".log")).open("w", encoding="utf-8")
        process = subprocess.Popen([GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                                    "--script", "res://tests/fs_enet_acceptance.gd"],
                                   env=env, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        processes.append((role, process, log))
        if role == "host":
            wait(lambda: snapshot("host")["members"] == 1)
    wait(lambda: snapshot("host")["members"] == 2)
    send("host", "start")
    wait(lambda: snapshot("client")["in_game"])
    send("host", "passive_fixture", "automation_choice")
    wait(lambda: snapshot("client")["view"].get("card_automated", False)
         and snapshot("client")["view"].get("card_choices"))
    host = snapshot("host")["view"]
    client = snapshot("client")["view"]
    check(client["seat"] == 1 and client["actor"] == 1, "Выбор принадлежит клиенту")
    check(not host["card_choices"], "Варианты чужого выбора хосту в обычный view не отправляются")
    check(client["players"][1]["coins"] == 1, "Ресурс карты выдан до выбора автоматически")
    check(all("hand" not in p for p in client["players"]), "Нет закрытых рук в публичных строках")
    index = next(i for i, label in enumerate(client["card_choices"]) if "G Fuel" in label)
    revision = client["revision"]
    send("client", "effect", {"op": "coins", "amount": 99})
    client_barrier()
    wait(lambda: snapshot("host")["view"]["revision"] == revision)
    check(snapshot("host")["view"]["players"][1]["coins"] == 1, "Клиент не подменил эффект произвольной выплатой")
    send("host", "card_choice", {"index": index, "revision": revision})
    check(snapshot("host")["view"]["revision"] == revision, "Хост обычным действием не выбрал вместо клиента")
    send("client", "card_choice", {"index": index, "revision": revision - 1})
    client_barrier()
    check(snapshot("host")["view"]["revision"] == revision, "Устаревший выбор отклонён")
    send("client", "card_choice", {"index": index, "revision": revision})
    wait(lambda: snapshot("host")["view"]["phase"] == "turn")
    wait(lambda: snapshot("client")["view"]["phase"] == "turn")
    for role in ["host", "client"]:
        view = snapshot(role)["view"]
        check(not next(p for p in view["players"][0]["items"] if p["id"] == 40)["tapped"], "Обе стороны видят заряд после выбора")
        check(view["players"][1]["coins"] == 1, "Начисление не повторилось после выбора")
    send("client", "card_choice", {"index": index, "revision": revision})
    client_barrier()
    check(snapshot("host")["view"]["phase"] == "turn", "Повтор старого запроса не возобновил карту")
    print(f"FS AUTOMATION ENET: {checks} проверок / 0 ошибок · {OUT}")
finally:
    for role, process, log in processes:
        if process.poll() is None:
            try:
                send(role, "quit")
                process.wait(3)
            except (AssertionError, subprocess.TimeoutExpired):
                process.terminate()
                process.wait(3)
        log.close()
