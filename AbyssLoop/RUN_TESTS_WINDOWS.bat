@echo off
setlocal EnableExtensions
if "%ABYSS_LOOP_TEST_WORKERS%"=="" set "ABYSS_LOOP_TEST_WORKERS=4"
cd /d "%~dp0"
echo ==============================================
echo ABYSS LOOP - STATIC + ISOLATED GODOT 4.7.2 RC7
echo ==============================================
py -3 tests\run_static_suite.py
if errorlevel 1 (
  echo.
  echo Static/regression suite failed. Read tests\reports\STATIC_TEST_REPORT.txt
  exit /b 1
)
py -3 tools\release_preflight.py --expected-version 0.61.0 --require-static-report
if errorlevel 1 (
  echo.
  echo Independent release preflight failed. See tests\reports\RELEASE_CANDIDATE_PREFLIGHT_RU.md
  exit /b 2
)
if "%GODOT_EXE%"=="" set "GODOT_EXE=godot"
set "GODOT_CMD="
if exist "%GODOT_EXE%" set "GODOT_CMD=%GODOT_EXE%"
if not defined GODOT_CMD for /f "delims=" %%G in ('where "%GODOT_EXE%" 2^>nul') do if not defined GODOT_CMD set "GODOT_CMD=%%G"
if not defined GODOT_CMD (
  echo.
  echo Static suite and preflight passed, but Godot was not found.
  echo Set GODOT_EXE to the full path of Godot_v4.7.2-stable_win64.exe and rerun.
  exit /b 3
)
py -3 tools\run_runtime_gate.py --godot "%GODOT_CMD%" --package-output "%CD%\..\AbyssLoop_Godot_Prototype_61_RUNTIME_TESTED.zip"
if errorlevel 1 exit /b 4
echo PASS: Prototype 61 runtime gate passed. See tests\reports\RUNTIME_GATE_REPORT_RU.md
exit /b 0
