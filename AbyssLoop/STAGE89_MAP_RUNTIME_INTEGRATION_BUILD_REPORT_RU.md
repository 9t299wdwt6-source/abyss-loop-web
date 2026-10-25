# Stage 89 — Map runtime integration gate

Проект `0.61.0`; релизный статус: runtime не подтверждён.

## Что изменено

В существующий runtime acceptance, исполняющийся на настоящей сцене `MainScene` в CI, добавлены контракты для карты разведки и сохранений. Тест проверяет положительный `route_geometry_seed`, стартовую непустую маску `discovered_world_cells`, canonical IDs вида `m:col:row`, запрет появления дорожных клеток в маске и расширение разведанной области после вызова reveal helper на отдалённом узле маршрута.

Сценарий далее проверяет, что снимок сохраняет ту же discovery mask и seed геометрии, а свежий `ExpeditionManager` восстанавливает ровно ту же маску. Наконец, из копии снимка удаляется поле `discovered_world_cells`; восстановление должно открыть все 232 клетки вне дороги и не включать дорогу. Это проверяет прежний контракт совместимости Stage 88 на уровне реального GDScript runtime, как только CI запустит runner.

Новый `tests/stage89_map_runtime_gate_regression.py` обеспечивает source-level контроль содержимого теста и его подключения к существующему GitHub Actions runtime runner. Пакет релиза и независимый preflight включают отчёт и чек-лист Stage 89.

## Проверка в этой среде

- Stage 88 baseline: full static suite `114/114 PASS`.
- Web QA старого deploy из GitHub Actions (2026-10-24): `PASS` для WebGL 2, JS/WASM/PCK, desktop/phone viewport, pointer/touch placement и save/reload-resume. Этот результат относится к предыдущей опубликованной сборке.
- Повторный local Chromium run не смог открыть временный localhost URL (`ERR_BLOCKED_BY_ADMINISTRATOR`); `curl` не смог разрешить домен GitHub Pages из-за недоступного DNS.
- Godot 4.7.2 в среде отсутствует, а сетевой загрузчик недоступен. Реальное исполнение новой GDScript приёмки не заявляется.

## Результат

Stage 89 runtime gate добавлен в проект и будет исполняться существующим workflow при импорте проекта через Godot 4.7.2. Требуются свежий CI запуск и браузерная приёмка обновлённой сборки перед тем, как объявить runtime пройденным.
