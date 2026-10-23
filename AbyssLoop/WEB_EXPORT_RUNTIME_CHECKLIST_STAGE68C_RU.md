# Stage68C — чек-лист runtime-приёмки Web-сборки

Целевой движок: **Godot 4.7.2 stable**. Целевой графический API: **WebGL 2.0**.

## Текущий статус

**Web-экспорт, runtime-приёмка Godot, Chromium smoke, pointer interaction и публикация прошли успешно.**
URL: https://9t299wdwt6-source.github.io/abyss-loop-web/

Последний успешный pipeline: https://github.com/9t299wdwt6-source/abyss-loop-web/actions/runs/40022721056

## A. Godot, экспорт и артефакты

- [x] Godot 4.7.2 stable и Web export templates устанавливаются с проверкой SHA-256.
- [x] Ресурсы проекта импортируются без ошибок.
- [x] `index.html`, `index.js`, `index.wasm` и `index.pck` создаются и не пусты.
- [x] Web export preflight проходит без FAIL.
- [x] Python static/regression suite: **81/81 PASS**.
- [x] Godot smoke-suite исполняется внутри тестовой сцены с доступными autoload.
- [x] Расширенная Godot runtime-приёмка: **41 PASS** — меню, обучение, экспедиция, seed, запрещённое/допустимое размещение, событие/выбор, бой/награда, checkpoint save/restore, завершение забега и debrief.
- [x] Настоящий export проходит Chromium smoke: HTTP 200, canvas, WebGL 2, JS/WASM/PCK, MIME WASM, отсутствие JS/console errors и failed runtime requests.
- [x] Chromium pointer flow закрывает onboarding и запускает экспедицию; screenshot и JSON отчёт архивированы.
- [x] Публикация GitHub Pages завершена.

## B. Браузеры и устройства

- [ ] Проверить актуальный Chrome/Firefox/Edge на физическом desktop/laptop, включая повторный запуск.
- [ ] Проверить Safari на физическом iPhone: touch, portrait/landscape, keyboard, background/resume, reload/save.
- [ ] Убедиться, что браузерное сохранение сохраняется на том же origin и корректно обрабатывает пустой storage.

## C. Игровые сценарии

- [x] Первый запуск: главное меню и onboarding открываются, onboarding можно завершить.
- [x] Начало экспедиции происходит после настоящего pointer-клика в Chromium.
- [x] Godot runtime проверяет размещение тайла на дороге и ландшафте, а также отклонение запрещённой клетки.
- [x] Godot runtime проверяет событие, доступный выбор, блокировку размещения до решения и запись event history.
- [x] Godot runtime проверяет базовое прохождение боя, регистрацию победы/награды, save/restore и возврат на базу.
- [ ] Вручную пройти обычные бои, все эффекты состояния, элиту, телеграфы фаз боссов и длинную экспедицию.
- [ ] Выполнить тест сохранения/перезагрузки на опубликованном Web origin в браузере пользователя.

## D. Предупреждения и release gate

- [ ] Проверить, что debug-only diagnostics и clipboard недоступны/безопасны в release Web.
- [ ] Завершить ручную приёмку Safari/iPhone и touch.
- [ ] Сохранить скриншоты и отчёты нового viewport matrix после его включения в pipeline.
- [x] Подтверждено, что smoke тест не равен полному прохождению игры.

**Итог:** build/export/runtime/Chromium interaction gate зелёный. Stage64B balance capture и ручная мобильная/полная игровая приёмка остаются открыты; 1.0 не объявлена.
