@echo off
rem Runs GSUhub locally: the Supabase stack, the Auth emulator, the web app.
rem Options are documented at the top of run_local.ps1, e.g.
rem   tool\run_local.cmd -Server      serve at http://localhost:5556
rem   tool\run_local.cmd -Reseed      load the demo data again
rem   tool\run_local.cmd -Stop        stop everything
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_local.ps1" %*
exit /b %ERRORLEVEL%
