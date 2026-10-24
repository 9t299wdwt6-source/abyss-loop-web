# Abyss Loop — Web

Браузерная версия Abyss Loop на Godot 4.7.2.

## Играть

**[Запустить Abyss Loop в браузере](https://9t299wdwt6-source.github.io/abyss-loop-web/)**

## Последняя подтверждённая сборка

GitHub Actions: [последняя успешная сборка, 12-цикловая runtime-приёмка, Chromium gameplay flow и деплой](https://github.com/9t299wdwt6-source/abyss-loop-web/actions/runs/40073910109).

- Godot 4.7.2: импорт и Web-экспорт — PASS.
- Static/regression suite — **81/81 PASS**.
- Godot gameplay runtime — **41 проверки PASS**: новая экспедиция, дорожное/ландшафтное размещение, событие, бой, checkpoint save/restore, возврат с debrief.
- Chromium smoke — **PASS**: WebGL 2, JS/WASM/PCK, HTTP/MIME, без JS/console errors.
- Chromium pointer flow — **PASS**: реальные клики закрывают tutorial и открывают экспедицию.
- GitHub Pages deployment — **PASS**.

QA-артефакт с JSON-отчётами и скриншотами доступен в разделе Artifacts этого запуска.

## Репозиторий и разработка

Godot-исходники расположены в `AbyssLoop/`.

- [Инструкция сборки и Web QA](WEB_DEPLOYMENT_GUIDE_RU.md)
- [Workflow экспорта, тестирования и публикации](.github/workflows/abyssloop-web.yml)
- [Актуальная дорожная карта разработки](AbyssLoop/ROADMAP_STATUS_STAGE69_RU.md)

## Оставшиеся проверки

Автоматические проверки не заменяют полное прохождение: нужно отдельно проверить босса и длинную экспедицию, сохранение после reload, сенсорное управление и Safari на реальном iPhone. Stage64B real-run balance capture ещё открыт; версия 1.0 не объявлена готовой.
