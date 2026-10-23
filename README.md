# Abyss Loop — Web

Репозиторий браузерной версии Abyss Loop на Godot 4.7.2.

## Статус проекта

- Исходная база: **Prototype 61 RC7 / Stage68C Web Export Pipeline**.
- GitHub Actions workflow настроен: импорт исходников, Python-регрессии, экспорт HTML5/WebAssembly, Chromium smoke-test и GitHub Pages.
- **Игровой ZIP ещё не загружен в этот репозиторий**, поэтому сборка и публичный запуск пока не подтверждены.

## Следующий шаг

Однократно загрузите `AbyssLoop_Prototype61_Stage68C_Web_Export_Pipeline.zip` в корень репозитория через **Add file → Upload files** и нажмите **Commit changes** в ветку `main`. Workflow проверит SHA-256, распакует проект, сохранит обычные файлы исходников в `AbyssLoop/` и продолжит сборку.

Затем в **Settings → Pages → Build and deployment → Source** выберите **GitHub Actions**.

Полная последовательность описана в [руководстве по публикации](WEB_DEPLOYMENT_GUIDE_RU.md). Workflow: [Abyss Loop Web Export and Browser QA](.github/workflows/abyssloop-web.yml).

## Ожидаемый адрес

https://9t299wdwt6-source.github.io/abyss-loop-web/

Адрес не считается рабочим до успешного завершения GitHub Actions и деплоя.