# Abyss Loop Web — сборка, проверка и публикация

## Текущий релиз

**[Запустить опубликованную игру](https://9t299wdwt6-source.github.io/abyss-loop-web/)**

- Релизный исходный коммит: `adcfd96c50cdb6e8571604ec308be8c994789641`.
- GitHub Actions: [успешная сборка и публикация](https://github.com/9t299wdwt6-source/abyss-loop-web/actions/runs/40016205413).
- Godot 4.7.2: импорт проекта и Web-экспорт — PASS.
- Static/regression suite: 81/81 PASS.
- Chromium Web smoke-test: PASS.
- GitHub Pages deployment: PASS.

В preflight остаётся одно предупреждение о вызове буфера обмена в отладочной функции диагностики. Оно не блокировало экспорт; всё равно следует проверить, что отладочная функция не доступна в release Web-сборке.

## Что делает workflow

Файл: `.github/workflows/abyssloop-web.yml`.

При изменениях исходников, тестов или самого workflow он:
1. Проверяет SHA-256 архивов Godot 4.7.2 и Web export templates.
2. Проверяет Web-настройки проекта, включая варианты сжатия текстур ETC2/ASTC и S3TC/BPTC.
3. Запускает Python static/regression suite.
4. Импортирует ресурсы Godot в headless-режиме.
5. Экспортирует `index.html`, `index.js`, `index.wasm` и `index.pck`.
6. Проверяет размеры и структуру экспортированных файлов.
7. Запускает Chromium smoke-test: HTTP, canvas, WebGL 2, runtime-файлы, MIME WASM, console и JavaScript errors.
8. Публикует артефакт на GitHub Pages только после успешных проверок.

## Как вносить дальнейшие изменения

Исходники проекта расположены в папке `AbyssLoop/`.

1. Измени нужные GDScript/сцены/настройки или тесты.
2. Отправь commit в ветку `main`.
3. Открой [GitHub Actions](https://github.com/9t299wdwt6-source/abyss-loop-web/actions) и проверь, что этапы сборки, Chromium smoke-test и deploy завершились успешно.
4. После успешного deploy проверь игру по опубликованной ссылке.

Изменения документации сами по себе не запускают сборку. Изменения `AbyssLoop/**/*.gd`, `*.tscn`, `*.tres`, `project.godot`, `export_presets.cfg`, `AbyssLoop/tools/web_*.py`, `AbyssLoop/tests/**` или `.github/workflows/**` запускают workflow.

## Что не покрывает автоматический smoke-test

Smoke-test подтверждает начальную загрузку настоящего Godot Web-экспорта в Chromium, но не полное прохождение. Вручную на опубликованном URL ещё нужно проверить:

- главное меню, запуск экспедиции, размещение тайлов на маршруте и ландшафте;
- обычный бой, эффекты состояний, события, элитного врага и босса;
- корректность наград, выхода и возврата в деревню/меню;
- сохранение после перезагрузки и восстановление прогресса;
- сенсорное управление и изменение ориентации;
- Safari на iPhone.

## Настройка GitHub Pages

Для текущего репозитория уже выбран источник **Settings → Pages → Build and deployment → Source → GitHub Actions**.

Публичный адрес: `https://9t299wdwt6-source.github.io/abyss-loop-web/`.
