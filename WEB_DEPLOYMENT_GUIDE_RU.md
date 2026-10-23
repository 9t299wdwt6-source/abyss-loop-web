# Публикация Abyss Loop Web через GitHub Pages

## Текущий статус

В репозитории размещён workflow `.github/workflows/abyssloop-web.yml`. Он умеет подготовить Godot 4.7.2, проверить исходный проект, экспортировать Web-версию, запустить Chromium smoke-test и публиковать Pages только после успешного теста.

**На текущем этапе исходники Godot-проекта ещё не загружены в репозиторий.** Поэтому workflow не следует запускать до появления `project.godot`, `export_presets.cfg`, `scenes/main.tscn`, `scripts/`, `assets/`, `localization/` и `tools/`.

## Как должен выглядеть корень репозитория

Основные файлы должны быть в корне репозитория, а не вложены в дополнительную папку:

- `project.godot`
- `export_presets.cfg`
- `scenes/main.tscn`
- `scripts/`
- `assets/`
- `localization/`
- `tools/export_web.sh`
- `tools/web_export_preflight.py`
- `tools/web_browser_smoke_test.py`
- `.github/workflows/abyssloop-web.yml`

## Первый запуск

1. Загрузить исходники проекта Prototype 61 RC7 / Stage68C в корень репозитория.
2. В GitHub открыть **Settings → Pages** и установить источник публикации **GitHub Actions**.
3. Открыть вкладку **Actions** и выбрать **Abyss Loop Web Export and Browser QA**.
4. Нажать **Run workflow** для ветки `main`.
5. Убедиться, что сборка, preflight и Chromium smoke-test завершились успешно.
6. После этого job `deploy` опубликует проверенный каталог `build/web`.

Ожидаемый адрес Pages: `https://9t299wdwt6-source.github.io/abyss-loop-web/`. Он не считается рабочим, пока публикация не прошла успешно.

## Проверки

Workflow проверяет:
- SHA-256 официального архива Godot и Web export templates;
- наличие и настройки исходного проекта;
- создание `index.html`, `.js`, `.wasm` и `.pck`;
- запуск страницы через Chromium, создание canvas, WebGL 2, загрузку артефактов и ошибки браузера;
- публикацию только после успешного smoke-test.

Chromium smoke-test — первичная проверка загрузки, а не полноценная игровая приёмка. После публикации нужно отдельно проверить игру в Safari на iPhone и основные игровые сценарии.
