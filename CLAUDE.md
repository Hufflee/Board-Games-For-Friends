# Настольные игры с друзьями

Сборник цифровых версий настольных игр для игры с друзьями (Steam / локальная сеть / один компьютер).
Godot **4.7**, GDScript, рендер Forward Plus (d3d12), физика Jolt. Главная сцена — хаб `res://hub/hub.tscn`.

Godot: `C:\Users\rabin\Desktop\ШТУКИ\godot\Godot_v4.7.2-stable_win64_console.exe` (console-версия — для запуска из терминала, видно вывод).

## Структура
- `hub/` — стартовый экран (неоновая комната, коробки игр, пати, приглашения Steam).
  `hub/games.gd` — **реестр игр**: новая игра = новая запись в `HubGames.LIST`. Обложки — `hub/covers/`.
- `games/<id>/` — каждая игра отдельно:
  - `logic/` — чистые правила без UI (`*_rules.gd`, `*_data.gd`, боты `*_bot.gd`). Всё тестируемо headless.
  - `ui/` — `main.tscn` → `*_app.gd` (корень: меню / лобби / стол), `*_lobby.gd`, `*_table.gd`, `*_style.gd` (мини-дизайн-система игры).
  - `art/`, `audio/` — ассеты игры.
  - Префиксы файлов по игре: `dw_` dangerous_words, `gl_` gloom, `hc_` hues_and_cues, `nh_` not_a_hat, `rsb_` ready_set_bet, `tt_` tip_top, `wl_` wavelength, `ws_` word_slam; у king_of_12 и perudo — без префикса / `perudo_`.
- `games/king_of_12/` — первая игра, из неё выросли **общие автозагрузки**: `Net` (net/net.gd), `Sfx`, `Prefs` (audio/), `K12UI` (ui_kit), `K12Tavern`. Их используют все игры.
- `docs/` — ТЗ на каждую игру (`TZ_<игра>.md`), `ui_tips.md`, `visual_design.md`, стайлборды `styleboard_*.png`, `КАК_ИГРАТЬ.md`.
- `tests/` — автотесты правил, `tools/` — служебные сцены (фазз, скриншоты, компиляция).
- `addons/godotsteam` — GodotSteam. `build/` — экспорт (в .gitignore).

## Сеть (Net) — важно
- Вся логика партии выполняется на **хосте** (peer 1). Клиенты только шлют `Net.send_action(...)` и получают своё состояние через сигнал `state_changed(view)`.
- Режимы: `offline` / `enet` / `steam`. Игры из `Net.LOCAL_GAMES` в офлайне — местные игроки (hot-seat), остальные — с ботами.
- Настройки всех игр лежат в `Net.settings` (ключи с префиксом игры). Новая игра → добавить свои ключи и, если нужно, в `LOCAL_GAMES`.
- Steam — только через `Engine.get_singleton("Steam")`: в редакторе аддон не грузится, код обязан работать без него.

## Как добавить новую игру
1. ТЗ в `docs/TZ_<id>.md` (по образцу существующих), при смене стиля — стайлборд на согласование.
2. `games/<id>/logic/` — правила + данные + (бот), затем `tests/test_<id>.gd`.
3. `games/<id>/ui/` — app / lobby / table / style + `main.tscn`, по образцу `games/perudo/ui/`.
4. Подключить к `Net` (действия, view для каждого места, настройки) и записать в `hub/games.gd`.
5. Прогнать тесты, compile и фазз (ниже).

## Проверки
```
# тесты правил одной игры (код выхода 1 при ошибке)
godot --headless --path . --script res://tests/test_perudo.gd
# все скрипты компилируются
godot --headless --path . res://tools/_fuzz/compile.tscn
# фазз-партия: env GAME, SCENE, BOTS, SPEED, MS, DARK=1, RESTART=1
godot --path . res://tools/_fuzz/fuzz.tscn
```
Тесты — простые `extends SceneTree` с `check(cond, msg)`, без фреймворка. Правила king_of_12 — `tests/test_rules.gd`.

## Стиль кода и UI
- Комментарии, строки UI, сообщения тестов — **на русском**. Док-комментарии `##` в начале файла: что это и как запускать.
- Типизированный GDScript (`var x := ...`, `-> void`), табы, `class_name` у логики (`PerudoRules`, `GLRules`…).
- UI строится в коде (сцены `main.tscn` минимальные), стили — в `*_style.gd` игры.
- Дизайн: 1 шрифт-заголовок + 1 текстовый, ≤3 размера, 2 основных цвета + нейтральные, сетка 8 px, один главный CTA, светлая и тёмная тема (`Prefs.theme_mode`). Подробно — `docs/ui_tips.md`, `docs/visual_design.md`.

## Ассеты и права
- Код проекта — под лицензией **PolyForm Noncommercial 1.0.0** (`LICENSE.md`): можно использовать и менять, но не в коммерческих целях. Текст лицензии не править.
- Часть арта (напр. `games/dangerous_words/art`, `games/gloom/art`) взята из оригинальных игр **только для личной игры с друзьями** — см. `SOURCE.txt`/`LICENSE.txt` рядом. Перед публикацией в Steam такой арт нужно заменить на свой.
- Свой арт можно генерировать локально через ComfyUI (`D:\AI\ComfyUI`, видеокарта GTX 1650 4 ГБ → модели SD 1.5, разрешение ~512–768 px, потом апскейл).

## Осторожно
- Проект **не под git** — откатить правки нельзя. Перед крупными изменениями — копия или `git init`.
- В проекте может параллельно работать другая сессия Claude: не править чужие файлы без нужды, не трогать `.godot/`.
