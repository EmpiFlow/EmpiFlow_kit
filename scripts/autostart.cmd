@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0autostart.ps1" %*
if "%1"=="-Remove" exit /b %ERRORLEVEL%
pause
exit /b %ERRORLEVEL%
