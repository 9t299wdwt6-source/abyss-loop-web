## Актуальная итерация механик — этап 71 (24.10.2026)

- Новая локальная сборка: `AbyssLoop_Prototype61_Stage71_Biome_Trophies_and_Tile_Relations.zip`.
- Дополнены тематические трофеи, постоянный бестиарий, амулетный аффикс для шанса трофея и рецепты синергии ландшафта.
- Статические проверки и ZIP integrity допускаются как evidence только после пересборки для этого commit; никакой runtime-tested статус не подразумевается.
- Компиляция Godot 4.7.2, in-engine smoke, сохранение/reload, полный баланс и браузерная публикация ещё не подтверждены.
- Полный отчёт: `STAGE71_BIOME_TROPHIES_AND_TILE_RELATIONS_BUILD_REPORT_RU.md`.

---

# Манифест сборки — Abyss Loop Prototype 61.0 RC7

- Официальное имя проекта и профиль сохранения: `Abyss Loop` (не менять ради прототипов).
- Версия проекта: `0.61.0`.
- Текущая механическая итерация: Stage 78 (предметное сравнение и походный тайник); текущая сборка остаётся статически проверенным кандидатом, не runtime-tested.
- Статус: **RELEASE CANDIDATE 7**. Без актуального `RUNTIME_GATE_REPORT_RU.md` runtime не подтверждён.
- Основная сцена: `res://scenes/main.tscn`.
- Целевая версия: Godot 4.7.2 stable, не RC/dev.
- Этап 61: длинные тексты модальных окон прокручиваются в ограниченной области; кнопки решений остаются видимыми вне скроллера; высокий контраст сохраняется при смене экранов.
- Этап 62 QA Hotfix: последовательный статический runner по умолчанию и безопасное завершение дерева процессов по тайм-ауту. Сама runtime-приёмка всё ещё не выполнена.
- Этап 64A: в ZIP включён симуляционный отчёт 144 сценариев × 100 прогонов; модель не заменяет реальные игровые измерения и балансные коэффициенты не менялись.
- Этап 65A: debug-диагностика выделена в отдельный read-only helper; UI и сохранения не менялись. Тесты проверяют, что helper включён в пакет.
- Текущий статус разработки: `ROADMAP_STATUS_STAGE65A_RU.md`; ручной шаблон реальных балансных замеров: `tests/reports/REAL_RUN_BALANCE_CAPTURE_TEMPLATE_STAGE64B_RU.md`.
- Дополнение дорожной карты: `ROADMAP_CONTINUATION_STAGES29-62_RU.md`.
- UI-приёмка: `UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md`.
- Чек-лист сквозного игрового цикла: `GAMEPLAY_CYCLE_RUNTIME_CHECKLIST_Prototype60.md`.
- Релизный чек-лист: `RELEASE_CANDIDATE_CHECKLIST_Prototype61.md`.
- Проверка сохранений: `SAVE_INTEGRITY_RUNTIME_CHECKLIST_Prototype59.md`.
- Предрелизный preflight: `py -3 tools\release_preflight.py --expected-version 0.61.0 --require-static-report`.
- Полный runtime gate на Windows: `RUN_RELEASE_GATE_WINDOWS.bat`.
- Runtime-tested ZIP допустим только после всех семи успешных ворот Godot 4.7.2 с совпадающим source fingerprint.
- ZIP содержит одну корневую папку `AbyssLoop/`; архив не включает пользовательские сохранения, секреты, кэши, временные файлы или другие ZIP.

**Ограничение:** RC7 не является релизом 1.0. Компиляцию и выполнение GDScript необходимо проверить реальным Godot 4.7.2, затем пройти ручной UI- и gameplay-чек-лист.

- Этап 68A: расширен статический граф ресурсов и согласованность `ExtResource` в сценах; тест включён в обязательный package/preflight контракт. Это не заменяет импорт в Godot 4.7.2.
- Последняя итерация: `ROADMAP_STATUS_STAGE68A_RU.md`; чек-лист финальной runtime-регрессии: `FINAL_REGRESSION_RUNTIME_CHECKLIST_STAGE68A_RU.md`.
- Stage68C: добавлены Web preset, воспроизводимый экспорт Godot 4.7.2, Playwright/Chromium smoke-test и GitHub Pages pipeline. Это только инфраструктурная подготовка: фактический Web export и публичный URL ещё не созданы; runtime не подтверждён.
