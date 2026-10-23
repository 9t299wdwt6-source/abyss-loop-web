# Abyss Loop — Web

Браузерная версия Abyss Loop на Godot 4.7.2.

## Играть

**[Запустить Abyss Loop в браузере](https://9t299wdwt6-source.github.io/abyss-loop-web/)**

Публикация GitHub Pages успешно завершена. Сборка экспортирована и прошла автоматическую проверку загрузки в Chromium.

## Проверенная сборка

- База проекта: **Prototype 61 RC7 / Stage68C Web Export Pipeline**.
- Godot 4.7.2: импорт ресурсов и Web-экспорт завершились успешно.
- Python static/regression suite: **81/81 PASS**.
- Chromium Web smoke-test: **PASS** — HTTP 200, canvas 1280×800, WebGL 2 доступен, JavaScript/WASM/PCK загружаются с HTTP 200, MIME WASM корректен, ошибок JavaScript/console и неудачных запросов нет.
- Деплой GitHub Pages: **успешен**.
- Web UI: заменены неподдерживаемые Unicode-иконки ресурсов на понятные текстовые обозначения.

[Результаты последнего GitHub Actions](https://github.com/9t299wdwt6-source/abyss-loop-web/actions/runs/40019051389)

## Репозиторий и pipeline

Исходники Godot находятся в `AbyssLoop/`.

- [Инструкция по сборке и публикации](WEB_DEPLOYMENT_GUIDE_RU.md)
- [Workflow экспорта, тестирования и публикации](.github/workflows/abyssloop-web.yml)

## Что ещё нужно проверить вручную

Chromium smoke-test подтверждает начальную загрузку Web-сборки, но не заменяет полное игровое прохождение. Следующий этап приёмки — проверить ключевые игровые сценарии, сохранение/загрузку, сенсорное управление, поворот экрана и Safari на iPhone.
