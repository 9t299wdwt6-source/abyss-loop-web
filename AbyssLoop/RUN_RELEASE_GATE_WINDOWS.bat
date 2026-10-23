@echo off
setlocal EnableExtensions
if "%ABYSS_LOOP_TEST_WORKERS%"=="" set "ABYSS_LOOP_TEST_WORKERS=4"
cd /d "%~dp0"
echo ==================================================
echo ABYSS LOOP - ISOLATED GODOT 4.7.2 RELEASE GATE RC7
echo ==================================================
echo.
if "%GODOT_EXE%"=="" set "GODOT_EXE=godot"
set "GODOT_CMD="
if exist "%GODOT_EXE%" set "GODOT_CMD=%GODOT_EXE%"
if not defined GODOT_CMD for /f "delims=" %%G in ('where "%GODOT_EXE%" 2^>nul') do if not defined GODOT_CMD set "GODOT_CMD=%%G"
if not defined GODOT_CMD (
  echo FAILED: Godot was not found.
  echo Set GODOT_EXE to the full path of Godot_v4.7.2-stable_win64.exe and run again.
  exit /b 2
)
echo Running source/document preflight...
py -3 tools\release_preflight.py --expected-version 0.61.0
if errorlevel 1 (
  echo FAILED: RC7 preflight did not pass. No runtime-tested ZIP will be created.
  exit /b 3
)
set "OUTPUT_ZIP=%CD%\..\AbyssLoop_Godot_Prototype_61_RUNTIME_TESTED.zip"
echo Godot executable: "%GODOT_CMD%"
echo Output: "%OUTPUT_ZIP%"
echo.
py -3 tools\run_runtime_gate.py --godot "%GODOT_CMD%" --package-output "%OUTPUT_ZIP%"
if errorlevel 1 (
  echo.
  echo FAILED: Prototype 61 release gate. See tests\reports\RUNTIME_GATE_FAILURE_REPORT_RU.md
  echo No runtime-tested ZIP should be distributed.
  exit /b 4
)
echo.
echo PASS: static checks, independent preflight, isolated editor import, clean launch,
echo gameplay smoke, save regression, integration audit, ZIP integrity and runtime report.
echo NOTE: visual acceptance and a full manual expedition are still required.
exit /b 0
