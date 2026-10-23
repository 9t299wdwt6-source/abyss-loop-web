# Stage68C — отчёт о Web-экспорте и runtime-приёмке

## Результат

**PASS: опубликованная Web-сборка с базовой автоматизированной runtime-приёмкой.**
Публичный URL: https://9t299wdwt6-source.github.io/abyss-loop-web/
Последний успешный CI: https://github.com/9t299wdwt6-source/abyss-loop-web/actions/runs/40022721056

## Результаты

- Официальный Godot 4.7.2 stable и Web export templates: установлены по SHA-256.
- Source preflight: 8/8 non-failing, 1 warning; ноль FAIL.
- Python static/regression: 81/81 passed.
- Godot runtime acceptance: 41/41 passed.
- Web export: PASS; обязательные HTML/JS/WASM/PCK присутствуют.
- Chromium Web smoke: PASS — HTML 200, WebGL 2, runtime assets 200, MIME WASM корректен, нет JS/console errors и failed JS/WASM/PCK requests.
- Chromium gameplay interaction: PASS — pointer-клик скрывает onboarding, следующий клик запускает экран экспедиции, canvas остаётся видимым.
- QA JSON/screenshots загружены в artifact `abyssloop-web-qa-8abe6b472a2e60747948d513029b0b7da486b84d`.
- Deploy job сообщил success и опубликовал build.

## Runtime-сценарий Godot (41 проверки)

Покрыты новая изолированная профиль-сессия, убежище и обучение, запуск с фиксированным seed, route count/hand, запрещённая стартовая клетка, дорожное и ландшафтное размещение, сохранение и восстановление snapshot, доступный выбор события, запрет размещения пока событие не решено, event history и счётчик, создание encounter, запрет размещения во время боя, победа и начисление награды, сохранение после изменений, завершение с outcome=return, удаление checkpoint, запись summary и возврат на убежище.

## История статуса релизного preflight

В исходном подготовительном отчёте Stage68C был записан статус «runtime не подтверждён». Это историческая отметка до появления Godot/Chromium CI runner; её оставили явно для проверки release-preflight, а актуальные runtime-результаты приведены выше и подтверждены запуском CI.

## Ограничения

Эта приёмка проверяет реальные игровые системы, но один runtime-сценарий не заменяет длинные независимые забеги. Отдельно требуется завершить Stage64B по reproducible real-run telemetry, ручной тест боссов/long expedition, проверку сохранения после browser reload на пользовательском origin и Safari/touch на физическом iPhone. Версия 1.0 не объявлена готовой.
