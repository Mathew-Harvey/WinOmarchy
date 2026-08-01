@echo off
rem Winmarchy dispatcher shim so "winmarchy" works from any shell.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0winmarchy.ps1" %*
exit /b %ERRORLEVEL%
