# Abyss Loop — Web

Репозиторий браузерной версии Abyss Loop на Godot 4.7.2.

## Состояние

- Исходная база: **Prototype 61 RC7 / Stage68C Web Export Pipeline**.
- GitHub Actions workflow добавлен: импорт исходников, Python-регрессии, Web-экспорт, Chromium smoke-test и публикация в GitHub Pages.
- Исходники Prototype 61 RC7 теперь находятся в `AbyssLoop/`.
- Первый запуск выявил две ошибки типизации в `scripts/ui/ui_controller.gd`; обе исправлены и отправлены в `main`. Повторная сборка проверяет экспорт и браузерный запуск.

## Что нужно сделать один раз

1. Откройте **Settings → Pages** и выберите **Build and deployment → Source → GitHub Actions**.
2. Загрузите `AbyssLoop_Prototype61_Stage68C_Web_Export_Pipeline.zip` в корень репозитория через **Add file → Upload files** и нажмите **Commit changes** в ветку `main`.
3. Workflow проверит архив, распакует исходники в `AbyssLoop/`, запустит тесты, экспортирует игру и опубликует результат при успешных проверках.

Инструкция: [Публикация через GitHub Pages](WEB_DEPLOYMENT_GUIDE_RU.md). Workflow: [Abyss Loop Web Export and Browser QA](.github/workflows/abyssloop-web.yml).

## Ожидаемый адрес

https://9t299wdwt6-source.github.io/abyss-loop-web/

Адрес не считается рабочим до успешного завершения GitHub Actions и деплоя.