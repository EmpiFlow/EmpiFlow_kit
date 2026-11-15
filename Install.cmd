@echo off
rem EmpiFlow kit - double-click this, or run it from a command prompt.
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" %*
set RC=%ERRORLEVEL%
rem 10 = this window handed over to the elevated window; close normally.
if "%RC%"=="10" exit /b 0
if "%~1"=="" pause
exit /b %RC%