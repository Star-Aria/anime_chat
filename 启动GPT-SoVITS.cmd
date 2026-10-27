@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start_gpt_sovits.ps1"
set "SOVITS_EXIT_CODE=%ERRORLEVEL%"
if not "%SOVITS_EXIT_CODE%"=="0" pause
exit /b %SOVITS_EXIT_CODE%
