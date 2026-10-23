# Автоматизированные проверки Abyss Loop

## 1. Python-регрессии и статическая целостность

В корне проекта выполните:

```powershell
py -3 tests\run_static_suite.py
```

Скрипт автоматически находит все `tests/*.py`, запускает каждый отдельным процессом, фиксирует код возврата/таймаут и сохраняет отчёт в `tests/reports/STATIC_TEST_REPORT.txt`. Это тесты исходников и регрессий; они не компилируют GDScript.

## 2. Godot runtime smoke test

При установленном Godot 4.7.2 выполните:

```powershell
godot --headless --path . --script res://tests/smoke_test.gd
```

Либо используйте `RUN_TESTS_WINDOWS.bat`. Если Godot не входит в PATH, укажите полный путь к исполняемому файлу в переменной окружения `GODOT_EXE`. Скрипт smoke test включает базовые проверки маршрута, тайлов, синергий, групп, фаз босса, событий, перков, целей, воспроизводимости seed и реестра контента.

## 3. Перед выпуском ZIP

1. Запустите Python suite и изучите полный отчёт, а не только итоговую строку.
2. Запустите Godot smoke test на целевой версии.
3. Вручную пройдите сценарии из `acceptance_matrix.md`, отдельно загрузив старое сохранение.
4. Сохраните отчёт и список непройденных ручных сценариев вместе с changelog.

Не называйте сборку проверенной в Godot, если запущен только Python suite.


### Матрица content 1.0 (Prototype 49)

Запустить `python tests/content_v1_matrix_regression.py`. Этот тест читает только литеральные константы, сравнивает stable ID с `tests/fixtures/content_v1_stable_ids.json`, проверяет поля и ссылочную целостность и генерирует `tests/reports/CONTENT_V1_READINESS_MATRIX_RU.md`. Это статический аудит; он не компилирует GDScript и не оценивает визуальные ресурсы в движке.


## Интеграционный аудит Prototype 54

В Godot 4.7.2 runtime-гейт дополнительно запускает `tests/expedition_integration_audit.gd` после `smoke_test.gd` и `save_system_regression.gd`. Он проверяет восстановление checkpoint, повторное событие, откат при невалидном сохранении и однократное завершение забега. Запускайте этот тест только в отдельной QA-копии; он сохраняет и восстанавливает целевые файлы профиля.


## Тайм-ауты runtime gate (этап 62B)

`tools/run_runtime_gate.py` использует общий процессный runner `tools/test_process_runner.py`. При тайм-ауте завершается вся группа процессов, а не только родительский процесс. Регрессия `tests/runtime_gate_process_cleanup_regression.py` проверяет нормальный выход, ненулевой exit code и потомка, удерживающего stdout. Она входит в `tests/run_static_suite.py`; отдельный запуск: `py -3 tests\runtime_gate_process_cleanup_regression.py`. Этот тест не заменяет запуск Godot и не является runtime-приёмкой самой игры.
