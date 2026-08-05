@echo off
rem Winmarchy dispatcher shim so "winmarchy" works from any shell.
rem
rem The installed copy lives in shim\, a directory holding nothing else, and
rem shim\ is what goes on PATH. bin\ is deliberately kept OFF the PATH even
rem though this file is there too: bin\ also holds winmarchy.ps1, and
rem PowerShell resolves a bare "winmarchy" to the .ps1 ahead of this .cmd,
rem then runs it inside the caller's own session, where the default
rem Restricted execution policy refuses it. Going through this file is the
rem only thing that supplies -ExecutionPolicy Bypass. See FLAGS.md FLAG-52.
rem
rem The path below resolves from either location: from shim\ it walks up and
rem across to bin\, and from bin\ itself it lands back on bin\.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\bin\winmarchy.ps1" %*
exit /b %ERRORLEVEL%
