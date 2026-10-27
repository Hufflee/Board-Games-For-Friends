"""Один хост + один настоящий loopback-клиент, 2 дополнительных local-места. Только свои процессы."""
from pathlib import Path
import json
import os
import socket
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/client_switch_audit" / ("enet-low-" + time.strftime("%H%M%S"))
GODOT = "C:/Users/rabin/Desktop/ШТУКИ/godot/Godot_v4.7.2-stable_win64_console.exe"
OUT.mkdir(parents=True)
processes, streams, ids = {}, [], {"host": 0, "client": 0}
checks = 0
games = os.environ.get("CS_GAMES", "wavelength,hues_and_cues,ready_set_bet").split(",")
if not games or games[0] != "wavelength":
    raise ValueError("Первой игрой сценария должна быть wavelength")
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as port_socket:
    port_socket.bind(("127.0.0.1", 0))
    port = port_socket.getsockname()[1]


def snapshot(role):
    try:
        return json.loads((OUT / f"{role}-snapshot.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def wait(role, predicate, label, seconds=55):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if processes[role].poll() is not None:
            raise AssertionError(f"{role}: процесс завершился раньше {label}, exit={processes[role].returncode}")
        state = snapshot(role)
        if state.get("errors"):
            raise AssertionError(f"{role}: ScriptError {state['errors'][0]}")
        if predicate(state):
            return state
        time.sleep(0.05)
    raise AssertionError(f"{role}: timeout {label}; {snapshot(role)}")


def check(ok, label):
    global checks
    checks += 1
    if not ok:
        raise AssertionError(label)


def launch(role):
    env = os.environ.copy()
    env.update(CS_ROLE=role, CS_OUT=OUT.as_posix(), CS_PORT=str(port), APPDATA=str(OUT / ("profile-" + role)))
    stdout = (OUT / (role + ".log")).open("w", encoding="utf-8")
    stderr = (OUT / (role + ".stderr.log")).open("w", encoding="utf-8")
    streams.extend([stdout, stderr])
    rendering = (["--rendering-method", "forward_plus", "--rendering-driver", "d3d12", "--position", "-32000,-32000"]
                 if role == "client" and os.environ.get("CS_RENDER") == "1" else ["--headless"])
    processes[role] = subprocess.Popen([GODOT, *rendering, "--audio-driver", "Dummy", "--max-fps", "120",
        "--path", str(ROOT), "--script", "res://tests/client_switch_net_probe.gd"], cwd=ROOT, env=env,
        stdout=stdout, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)


def command(role, kind, game=""):
    ids[role] += 1
    target = OUT / (role + "-command.json")
    temp = target.with_suffix(".tmp")
    temp.write_text(json.dumps({"id": ids[role], "kind": kind, "game": game}), encoding="utf-8")
    os.replace(temp, target)
    if kind != "quit":
        wait(role, lambda s: s.get("command") == ids[role], kind)


result = {"checks": 0, "errors": [], "transitions": [], "output": str(OUT),
          "client_render": "d3d12" if os.environ.get("CS_RENDER") == "1" else "headless"}
try:
    launch("host")
    wait("host", lambda s: s.get("mode") == "enet", "хост открыт")
    launch("client")
    wait("host", lambda s: s.get("members") == 2, "клиент присоединился")
    wait("client", lambda s: s.get("party") == "wavelength", "первое lobby")
    for index, game in enumerate(games):
        command("host", "start" if index == 0 else "switch", game)
        server = wait("host", lambda s: s.get("in_game") and s.get("view_game") == game, "старт " + game)
        client = wait("client", lambda s: s.get("in_game") and s.get("view_game") == game and s.get("table_game") == game,
                      "настоящий стол " + game)
        check(server["command_error"] == "", "Штатный старт без ошибки")
        check(server["places"] == 4 and server["members"] == 2, "Два реальных peer + два local-места")
        check(client["match"] == server["match"], "Клиент получил текущий match")
        check(client["scene"] == f"res://games/{game}/ui/main.tscn", "Правильная клиентская сцена")
        check(not client["errors"], "Ноль ошибок клиента")
        result["transitions"].append({k: client[k] for k in ["party", "view_game", "match", "scene", "table_game", "started_games", "warnings"]})
        print("CLIENT ENET СТОЛ:", game, flush=True)
    check(snapshot("client")["started_games"] == games, "Каждая игра запущена ровно один раз со свежим view")
except Exception as exc:
    result["errors"].append(str(exc))
finally:
    for role, process in processes.items():
        if process.poll() is None:
            command(role, "quit")
    for role, process in processes.items():
        try:
            process.wait(timeout=12)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=8)
            result["errors"].append(role + ": потребовался terminate своего процесса")
        result[role + "_exit"] = process.returncode
        if process.returncode != 0:
            result["errors"].append(f"{role}: exit{process.returncode}")
    for stream in streams:
        stream.close()
    # Нативная Steam-библиотека может напечатать SteamID даже при loopback/Dummy.
    # Сохраняем диагностическую строку, скрывая идентификатор в собственных журналах.
    for log_path in OUT.glob("*.log"):
        data = log_path.read_text(encoding="utf-8", errors="replace")
        data = re.sub(r"(Caching Steam ID:\s*)[0-9]+", r"\1[скрыт]", data)
        log_path.write_text(data, encoding="utf-8")
    result["checks"] = checks
    (OUT / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(1 if result["errors"] else 0)
