# Abyss Loop — hotfix 45.1: исправление ошибок загрузки GDScript

## Основание

Hotfix подготовлен по скриншотам запуска Prototype 45 в Godot 4.7.2.stable. Оригинальный архив Prototype 45 сохранён; игровые системы и `config/version="0.45.0"` не менялись.

## Исправления

1. `scripts/core/game_state.gd`: строка поясняющего текста `expedition risk still scale separately...` была без `#` и ошибочно разбиралась как код. Исправлено продолжение комментария.
2. `scripts/systems/expedition_manager.gd`: цикл восстановления снимка повторно объявлял `encounter_value`, уже использованный для источника массива. Переменная итератора переименована в `encounter_entry`.
3. `scripts/systems/tile_system.gd`: ведущие отступы нормализованы в единый стиль из четырёх пробелов, чтобы убрать смешение табуляции и пробелов.
4. `scripts/ui/ui_controller.gd`: вызов `Object.get("hovered_world_cell_id", "")` заменён на допустимый для `Object.get()` вызов с одним аргументом.
5. `scripts/ui/ui_controller.gd` и `scripts/systems/base_system.gd`: флаги affordability/equipped/checkpoint/research и числа для отката снабжены явными типами, чтобы снять ошибки вывода типов, указанные в логе.
6. `tests/smoke_test.gd`: второе объявление локальной переменной `boss_group` переименовано в `configured_boss_group`.
7. Добавлен `tests/godot_parse_hotfix_regression.py` (13 проверок), закрепляющий все исправленные классы ошибок.

## Проверки

- Static/regression suite: **51/51 PASS**.
- Hotfix-specific guards: **13/13 PASS**.
- ZIP integrity: **PASS**.
- Внутри ZIP ровно одна корневая папка: `AbyssLoop/`; точка входа `AbyssLoop/project.godot` присутствует.

## Честный статус runtime

В среде подготовки нет исполняемого файла Godot, и сетевой доступ для получения бинарного файла недоступен. Поэтому я не смог повторно скомпилировать все GDScript и запустить `tests/smoke_test.gd` в самом движке. Hotfix исправляет конкретные ошибки со скриншотов и проходит статические регрессии, но **не заявляется как runtime-tested**. После распаковки следует открыть `AbyssLoop/project.godot` в Godot 4.7.2 и запустить `RUN_RELEASE_GATE_WINDOWS.bat`; любые новые сообщения парсера нужно рассматривать отдельно.
