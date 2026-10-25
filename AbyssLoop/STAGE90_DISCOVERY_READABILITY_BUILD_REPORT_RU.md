# Stage 90 — читаемость карты исследования и компактное размещение

## Результат

В `RouteView` добавлен короткий заголовок для узкого экрана и счётчик исследования `РАЗВЕДАНО n/232`, расположенный вне интерактивной сетки. Счётчик считается только по валидным canonical ID `m:col:row`, `true` значениям и свободным от дороги клеткам текущей геометрии.

Неизведанные тайлы получают более плотную тёмную подложку, редкие seed/coordinate-детерминированные отметки и адаптивный маркер вопроса. В режиме размещения рисунок тумана не перекрывает индикатор предпросмотра. Индикатор валидности масштабируется с размером клетки и переходит на компактные знаки `+`/`X` на узких клетках. High-contrast имеет отдельные контрастные рамки и знаки.

## Тесты

Новый `tests/stage90_discovery_readability_regression.py` проходит **10/10 source contracts + 5 viewport-сценариев**. Полный набор проходит **116/116**; независимый release preflight — **7/7**; архивный аудит — **7/7**. Результаты полного набора находятся в `tests/reports/STATIC_TEST_REPORT.txt`.

## Ограничения

Этап не заявляется как runtime-tested. В этой среде нет исполняемого Godot 4.7.2; исходные проверки и геометрическая модель не доказывают отсутствие ошибок парсинга GDScript или корректную визуализацию в Web export. Для runtime-приёмки нужен свежий GitHub Actions workflow с Godot 4.7.2, Chromium screenshots и gameplay acceptance. Runtime/browser not confirmed.

Runtime acceptance: NOT RUN for Stage 90; runtime acceptance and browser rendering are not confirmed in this environment.
