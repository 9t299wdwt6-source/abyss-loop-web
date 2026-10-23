# Abyss Loop — Prototype 61.0 RC7

**Версия проекта:** `0.61.0`. Официальное имя приложения и профиль сохранения остаются `Abyss Loop`. Это релиз-кандидат для проверки, не финальная версия 1.0.

Prototype 61 продолжает этап 61 дорожной карты — финальную UI-проверку масштабирования, окон и локализации. Длинные тексты событий, обучения, справки и подтверждений помещаются в ограниченную вертикально прокручиваемую область; кнопки решений остаются за её пределами, чтобы не уезжать вслед за текстом. Сохранённый режим повышенной контрастности применяется повторно после перестроения убежища, экспедиции и модальных окон.

## Проверки

- Статические регрессионные тесты: `py -3 tests\run_static_suite.py`.
- Независимый preflight: `py -3 tools\release_preflight.py --expected-version 0.61.0 --require-static-report`.
- Сквозной runtime-аудит: `tests/expedition_integration_audit.gd` — включает возобновление, состояние RNG, антидублирование выбора события, транзакцию завершения и чтение полного результата обратно из сохранения.
- Чек-лист UI: `UI_ACCEPTANCE_RUNTIME_CHECKLIST_Prototype61.md`.
- Ручной чек-лист игрового цикла: `GAMEPLAY_CYCLE_RUNTIME_CHECKLIST_Prototype60.md`.
- Предрелизный чек-лист: `RELEASE_CANDIDATE_CHECKLIST_Prototype61.md`.

Статические проверки не подтверждают компиляцию GDScript или поведение движка. Для runtime-приёмки требуется Godot 4.7.2 stable и все семь успешных ворот `RUN_RELEASE_GATE_WINDOWS.bat` с актуальным fingerprint. Прежде чем объявлять релиз 1.0, нужно также вручную проверить размеры интерфейса, настройки доступности и полный игровой цикл.

См. `RELEASE_MANIFEST_RU.md`, `BUILD_REPORT_RU.md`, `ROADMAP_STATUS_RU.md`, `SAVE_INTEGRITY_RUNTIME_CHECKLIST_Prototype59.md` и `POST_RUN_DEBRIEF_RUNTIME_CHECKLIST_Prototype58.md`.
