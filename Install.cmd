@echo off
rem EmpiFlow kit - double-click this, or run it from a command prompt.
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%
