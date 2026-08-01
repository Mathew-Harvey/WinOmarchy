@echo off
rem Double-click entry point for the guided Winmarchy setup.
rem -STA is required: WPF cannot start on a multi-threaded apartment.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0install-ui.ps1" %*
exit /b %ERRORLEVEL%
