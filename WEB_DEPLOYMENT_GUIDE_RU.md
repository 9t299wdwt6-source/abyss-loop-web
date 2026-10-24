# Abyss Loop Web — сборка, тестирование и публикация

## Последний проверенный релиз

**[Запустить игру](https://9t299wdwt6-source.github.io/abyss-loop-web/)**

[Успешный pipeline: build + 81 static checks + Godot runtime + Chromium smoke/interaction + deploy](https://github.com/9t299wdwt6-source/abyss-loop-web/actions/runs/40022721056)

Проверенная база: Prototype 61 RC7 / Godot 4.7.2 / version 0.61.0.

## Что запускает workflow

Файл `.github/workflows/abyssloop-web.yml`. Изменения исходников, тестов и самого workflow запускают:
1. Проверку SHA-256 официальных архивов Godot 4.7.2 и Web export templates.
2. Source Web preflight и Python regression suite.
3. Импорт ресурсов Godot.
4. Оригинальный Godot smoke-suite, запускаемый через обычную сцену с доступными autoload.
5. Отдельную Godot runtime-приёмку меню, старта, seed, дорожного/ландшафтного размещения, события, боя, сохранения/восстановления и возврата на базу.
6. Web-экспорт HTML/JS/WASM/PCK.
7. Chromium Web smoke с проверкой WebGL 2, MIME WASM, загрузки файлов и отсутствия ошибок.
8. Chromium pointer flow, который настоящими кликами закрывает onboarding и запускает экспедицию.
9. Публикацию GitHub Pages только после успешного прохождения предыдущих шагов.

## Дальнейшая разработка

Актуальный статус этапов и блокирующих проверок ведётся в [ROADMAP_STATUS_STAGE69_RU.md](AbyssLoop/ROADMAP_STATUS_STAGE69_RU.md). Исторический Stage68C документ не является статусом последнего коммита.

Любые изменения Godot вносить в `AbyssLoop/`, затем отправлять в `main`. Успешная сборка подтверждает entry path и базовые сценарии, но не полное прохождение. Не закрыты: ручная проверка боссов/длинной экспедиции, user-origin save/reload, touch и Safari/iPhone. Stage64B баланс нужно оценивать на независимых воспроизводимых забегах обычного игрового цикла, а не на фикстурах со скриптово изменённым HP.

## GitHub Pages

Source настроен как **Settings → Pages → Build and deployment → Source → GitHub Actions**.
Публичный URL: `https://9t299wdwt6-source.github.io/abyss-loop-web/`.
